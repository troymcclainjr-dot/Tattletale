extends RefCounted
## Miss Bea's things: the furniture and fittings of an old lady's frame house
## (plans/bea.gd), in the style of props.gd. Each takes the place, the band,
## where on the plan (u, v), and which way its front faces (0 the street, 90
## right, 180 the back, 270 left), and takes up floor unless it says otherwise.
## Things on a wall are put ON the wall's face: give the point on the wall and
## the way the wall faces. Pieces that stand ON something (a doily, a photo, a
## lamp, a pie) take the group they stand in and a point on its top.
##
## Wall dressing (wallpaper stripes, a dado rail, clapboards) is built with
## `panel` and `stripes`: a wall is the one at `at` (place.gd's cross or side),
## `side` +1 is its face towards +z (cross) or +x (side), and `holes` are
## [from, to, y0, y1] rectangles to leave bare (doors, windows; see `holes`).

const Props := preload("res://scripts/props.gd")

const WALL := 0.075                          # half a wall's thickness (place.gd's T)
const WHITE := Color(0.94, 0.93, 0.87)       # painted trim
const LACE := Color(0.98, 0.97, 0.93)
const PLASTIC := Color(0.86, 0.93, 1.0, 0.26)   # the clear covers on the good furniture
const SHINE := Color(1.0, 1.0, 1.0, 0.7)
const MAHOGANY := Color(0.36, 0.16, 0.11)
const WALNUT := Color(0.42, 0.27, 0.16)
const BRASS := Color(0.82, 0.66, 0.28)
const LEAF := Color(0.24, 0.5, 0.24)
const SOIL := Color(0.24, 0.17, 0.12)
const SKIN := [Color(0.42, 0.26, 0.17), Color(0.55, 0.36, 0.22), Color(0.32, 0.2, 0.14), Color(0.62, 0.43, 0.3)]
const SUNDAY := [Color(0.55, 0.2, 0.6), Color(0.85, 0.15, 0.22), Color(0.96, 0.95, 0.9), Color(0.15, 0.3, 0.75), Color(0.95, 0.75, 0.2), Color(0.15, 0.55, 0.45)]
const BLOOMS := [Color(0.95, 0.25, 0.32), Color(0.99, 0.82, 0.2), Color(0.98, 0.58, 0.78), Color(0.62, 0.38, 0.9), Color(0.99, 0.97, 0.92), Color(1.0, 0.52, 0.15)]


static func _pick(list: Array, key: float) -> Color:
	return list[int(Props.rnd(key) * list.size()) % list.size()]


# ----------------------------------------------------------- wall dressing

## The rectangles round a wall's openings (place.gd's openings, as given to
## cross or side), widened to clear their frames: [from, to, y0, y1].
static func holes(openings: Array) -> Array:
	var out: Array = []
	for op: Dictionary in openings:
		var kind: String = op.get("kind", "door")
		var sill: float = op.get("sill", 0.95 if kind == "window" else 0.0)
		var head: float = op.get("head", 2.1 if kind == "window" else (2.3 if kind == "arch" else 2.05))
		out.append([op["a"] - 0.07, op["b"] + 0.07, sill - 0.07 if sill > 0.0 else -1.0, head + 0.07])
	return out


## A sheet on one face of a wall, `depth` thick, standing `off` off the face:
## from..to along the wall, y0..y1 high, cut round the holes.
static func panel(p: Node3D, n: Node3D, along_u: bool, at: float, from: float, to: float, side: float, y0: float, y1: float, depth: float, look: Variant, hole_list := [], off := 0.0, inset := 0.0) -> void:
	var ys: Array = [y0, y1]
	for h: Array in hole_list:
		for y: float in [h[2], h[3]]:
			if y > y0 + 0.001 and y < y1 - 0.001 and not ys.has(y):
				ys.append(y)
	ys.sort()
	var face := at + side * (WALL + off + depth * 0.5)
	for i in ys.size() - 1:
		var lo: float = ys[i]
		var hi: float = ys[i + 1]
		var cuts: Array = []
		for h: Array in hole_list:
			if h[2] <= lo + 0.001 and h[3] >= hi - 0.001 and h[1] > from and h[0] < to:
				cuts.append([h[0], h[1]])
		cuts.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var cursor := from
		for c: Array in cuts:
			if c[0] > cursor + 0.01 + inset * 2.0:
				p.slab(n, along_u, face, cursor + inset, c[0] - inset, lo, hi, depth, look)
			cursor = maxf(cursor, c[1])
		if to > cursor + 0.01 + inset * 2.0:
			p.slab(n, along_u, face, cursor + inset, to - inset, lo, hi, depth, look)


## Upright stripes on a wall face (wallpaper, the grooves of boarding), every
## `every` metres, `wide` wide, cut round the holes.
static func stripes(p: Node3D, n: Node3D, along_u: bool, at: float, from: float, to: float, side: float, y0: float, y1: float, look: Variant, every := 0.32, wide := 0.06, hole_list := [], off := 0.006) -> void:
	var x := from + every * 0.5
	while x < to - wide * 0.5:
		var runs: Array = [[y0, y1]]
		for h: Array in hole_list:
			if x + wide * 0.5 > h[0] and x - wide * 0.5 < h[1]:
				var left: Array = []
				for s: Array in runs:
					if h[3] <= s[0] or h[2] >= s[1]:
						left.append(s)
						continue
					if h[2] > s[0]:
						left.append([s[0], h[2]])
					if h[3] < s[1]:
						left.append([h[3], s[1]])
				runs = left
		for s: Array in runs:
			if s[1] - s[0] > 0.04:
				p.slab(n, along_u, at + side * (WALL + off + 0.003), x - wide * 0.5, x + wide * 0.5, s[0], s[1], 0.006, look)
		x += every


## A papered room's wall: stripes over the paper, a wainscot below a dado
## rail, a skirting board. `paper` (or null) is laid over the face first, for
## a wall whose own look belongs to the room on its other side.
static func papered(p: Node3D, n: Node3D, along_u: bool, at: float, from: float, to: float, side: float, stripe: Variant, wainscot: Variant, rail: Color, hole_list := [], paper: Variant = null, dado := 0.9, every := 0.34, wide := 0.07) -> void:
	if paper != null:
		panel(p, n, along_u, at, from, to, side, dado, 2.86, 0.005, paper, hole_list)
	if stripe != null:
		stripes(p, n, along_u, at, from, to, side, dado + 0.06, 2.86, stripe, every, wide, hole_list)
	# Each layer stands its own hair off the wall and stops its own hair short
	# of the ends, so no two faces lie on one another.
	panel(p, n, along_u, at, from, to, side, 0.0, dado - 0.005, 0.016, wainscot, hole_list, 0.002)
	panel(p, n, along_u, at, from, to, side, dado - 0.01, dado + 0.05, 0.036, rail, hole_list, 0.004, 0.004)
	panel(p, n, along_u, at, from, to, side, 0.0, 0.14, 0.026, rail.darkened(0.15), hole_list, 0.005, 0.008)


## Clapboards: a shadow line under each board, every `gap` metres up the face.
static func siding(p: Node3D, n: Node3D, along_u: bool, at: float, from: float, to: float, side: float, y0: float, y1: float, line: Color, hole_list := [], gap := 0.2) -> void:
	var y := y0 + gap
	while y < y1 - 0.03:
		panel(p, n, along_u, at, from, to, side, y, y + 0.03, 0.012, line, hole_list)
		y += gap


# -------------------------------------------------------------------- lace

## A round lace mat lying on something: `pos` is the point on its top.
static func doily(parent: Node3D, pos: Vector3, r := 0.15) -> void:
	Kit.cyl(parent, r, 0.006, pos + Vector3(0, 0.003, 0), LACE, Vector3.ZERO, 16)
	Kit.cyl(parent, r * 0.5, 0.004, pos + Vector3(0, 0.007, 0), LACE.darkened(0.1), Vector3.ZERO, 10)
	for i in 10:
		var a := TAU * i / 10.0
		Kit.cyl(parent, r * 0.22, 0.006, pos + Vector3(cos(a) * r, 0.003, sin(a) * r), LACE, Vector3.ZERO, 8)


## A lace cloth laid over a chair or sofa back and hanging down its front:
## `top` is the middle of the back's top, `front` how far its face is in front.
static func drape(parent: Node3D, top: Vector3, w: float, front: float, drop := 0.24) -> void:
	Kit.box(parent, Vector3(w, 0.01, front * 2.0 + 0.03), top + Vector3(0, 0.005, 0), LACE)
	Kit.box(parent, Vector3(w, drop, 0.01), top + Vector3(0, -drop * 0.5, front + 0.01), LACE)
	var n := maxi(int(w / 0.075), 3)
	for i in n:
		Kit.cyl(parent, w / n * 0.5, 0.01, top + Vector3(-w * 0.5 + (i + 0.5) * w / n, -drop, front + 0.01), LACE, Vector3(90, 0, 0), 8)


## A runner along the top of something, hanging a little over each end.
static func runner(parent: Node3D, top: Vector3, w: float, d: float, over := 0.12) -> void:
	Kit.box(parent, Vector3(w, 0.006, d), top + Vector3(0, 0.003, 0), LACE)
	for side: float in [-1.0, 1.0]:
		Kit.box(parent, Vector3(0.006, over, d), top + Vector3(side * (w * 0.5 + 0.003), 0.004 - over * 0.5, 0), LACE)
		for k in 3:
			Kit.cyl(parent, d / 6.0, 0.006, top + Vector3(side * (w * 0.5 + 0.003), -over, -d * 0.5 + (k + 0.5) * d / 3.0), LACE, Vector3(0, 0, 90), 8)


# ----------------------------------------------------------------- pictures

## A framed photograph standing on something, leaning back a little. `key`
## picks the frame, the backdrop and who is in it.
static func photo(parent: Node3D, pos: Vector3, w := 0.16, h := 0.21, yaw := 0.0, key := 0.0) -> Node3D:
	var f := Kit.group(parent, pos, Vector3(0, yaw, 0))
	var lean := Kit.group(f, Vector3.ZERO, Vector3(-9, 0, 0))
	var frame := _pick([BRASS, Props.WOOD_DARK, Color(0.9, 0.88, 0.8), MAHOGANY, Color(0.75, 0.75, 0.78)], key)
	Kit.box(lean, Vector3(w, h, 0.022), Vector3(0, h * 0.5, 0), frame)
	_sitter(lean, Vector3(0, h * 0.5, 0.011), w * 0.8, h * 0.8, key)
	Kit.box(f, Vector3(0.016, h * 0.8, 0.016), Vector3(0, h * 0.4, -h * 0.28), frame.darkened(0.3), Vector3(28, 0, 0))   # the strut behind
	return f


## The picture inside a frame: a studio backdrop and someone's head and shoulders.
static func _sitter(parent: Node3D, mid: Vector3, w: float, h: float, key: float) -> void:
	var back := _pick([Color(0.62, 0.72, 0.88), Color(0.82, 0.7, 0.5), Color(0.72, 0.62, 0.76), Color(0.62, 0.78, 0.64), Color(0.86, 0.8, 0.66)], key + 1.0)
	Kit.box(parent, Vector3(w, h, 0.006), mid + Vector3(0, 0, 0.003), back)
	var skin := _pick(SKIN, key + 2.0)
	var cloth := _pick(SUNDAY, key + 3.0)
	if Props.rnd(key + 5.0) > 0.7:
		cloth = Color(0.12, 0.12, 0.16)        # a cap and gown, or a Sunday suit
	Kit.box(parent, Vector3(w * 0.7, h * 0.3, 0.006), mid + Vector3(0, -h * 0.35, 0.006), cloth)
	Kit.disc(parent, w * 0.27, mid + Vector3(0, h * 0.13, 0.006), Color(0.1, 0.08, 0.08), 0.006, 12)
	Kit.disc(parent, w * 0.22, mid + Vector3(0, h * 0.06, 0.009), skin, 0.006, 12)


## A framed picture hung on a wall: a portrait, or (kind "scene") a landscape,
## or (kind "words") a stitched sampler with `text` on it.
static func wall_picture(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 0.4, h := 0.5, y := 1.7, kind := "portrait", key := 0.0, text := "") -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.06, false)
	var frame := _pick([BRASS, Props.WOOD_DARK, MAHOGANY], key) if kind != "words" else Props.WOOD
	var z := 0.015              # clear of the wallpaper's stripes
	Kit.box(g, Vector3(w, h, 0.026), Vector3(0, y, z + 0.013), frame)
	Kit.box(g, Vector3(w - 0.08, h - 0.08, 0.006), Vector3(0, y, z + 0.029), frame.lightened(0.25))
	var inner := Vector3(0, y, z + 0.032)
	match kind:
		"scene":
			Kit.box(g, Vector3(w - 0.12, (h - 0.12) * 0.55, 0.006), inner + Vector3(0, (h - 0.12) * 0.22, 0.003), Color(0.55, 0.72, 0.85))
			Kit.box(g, Vector3(w - 0.12, (h - 0.12) * 0.45, 0.006), inner + Vector3(0, -(h - 0.12) * 0.27, 0.005), Color(0.35, 0.55, 0.3))
			Kit.disc(g, (h - 0.12) * 0.12, inner + Vector3((w - 0.12) * 0.25, (h - 0.12) * 0.3, 0.008), Color(0.98, 0.88, 0.5), 0.006, 10)
		"words":
			Kit.box(g, Vector3(w - 0.12, h - 0.12, 0.006), inner + Vector3(0, 0, 0.003), Color(0.95, 0.92, 0.82))
			Props.words(g, text, inner + Vector3(0, 0.02, 0.009), minf(0.07, (w - 0.16) / maxf(text.length(), 1.0) * 1.6), Color(0.62, 0.16, 0.2))
			for x: float in [-(w - 0.2) * 0.5, (w - 0.2) * 0.5]:
				Kit.disc(g, 0.025, inner + Vector3(x, -(h - 0.12) * 0.3, 0.008), Color(0.85, 0.3, 0.4), 0.006, 8)
			Kit.box(g, Vector3(w - 0.2, 0.012, 0.004), inner + Vector3(0, (h - 0.12) * 0.36, 0.008), Color(0.3, 0.5, 0.3))
			Kit.box(g, Vector3(w - 0.2, 0.012, 0.004), inner + Vector3(0, -(h - 0.12) * 0.36, 0.008), Color(0.3, 0.5, 0.3))
		_:
			_sitter(g, inner, w - 0.12, h - 0.12, key)
	return g


## A mirror on a wall, oval in a gilt frame.
static func mirror(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 0.55, h := 0.75, y := 1.6) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.06, false)
	var oval := Kit.cyl(g, w * 0.5, 0.03, Vector3(0, y, 0.03), BRASS, Vector3(90, 0, 0), 18)
	oval.scale = Vector3(1, 1, h / w)
	var glass := Kit.cyl(g, w * 0.5 - 0.04, 0.03, Vector3(0, y, 0.036), Color(0.7, 0.8, 0.86), Vector3(90, 0, 0), 18)
	glass.scale = Vector3(1, 1, (h - 0.08) / (w - 0.08))
	Kit.box(g, Vector3(0.1, 0.03, 0.006), Vector3(-w * 0.12, y + h * 0.18, 0.054), Color(1, 1, 1, 0.6), Vector3(0, 0, 35))
	return g


## A wall calendar from her own shop: a picture at the top, the shop's name,
## the month in a grid with a day ringed.
static func calendar(p: Node3D, b: int, u: float, v: float, yaw := 0.0, y := 1.55, month := "", size := 1.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.42 * size, 0.05, false)
	var s := Kit.group(g, Vector3(0, y, 0))
	s.scale = Vector3.ONE * size
	var z := 0.02
	Kit.box(s, Vector3(0.012, 0.012, 0.03), Vector3(0, 0.36, z), Props.DARK)                   # the nail
	Kit.box(s, Vector3(0.4, 0.7, 0.008), Vector3(0, 0, z), Props.PAPER)
	Kit.box(s, Vector3(0.36, 0.22, 0.006), Vector3(0, 0.22, z + 0.006), Color(0.55, 0.75, 0.9))    # the picture: a bowl of fruit
	Kit.box(s, Vector3(0.32, 0.07, 0.006), Vector3(0, 0.145, z + 0.008), Color(0.55, 0.36, 0.2))
	for k in 5:
		Kit.ball(s, 0.035, Vector3(-0.1 + k * 0.05, 0.2 + 0.03 * (k % 2), z + 0.012), _pick([Color(0.9, 0.2, 0.15), Color(0.98, 0.75, 0.15), Color(0.4, 0.7, 0.25), Color(0.6, 0.25, 0.6)], k * 2.7), 7)
	var green := Color(0.16, 0.36, 0.28)          # the grocery's own green (plans/store.gd)
	Kit.box(s, Vector3(0.38, 0.11, 0.006), Vector3(0, 0.055, z + 0.006), green)
	Props.words(s, "MISS BEA'S", Vector3(0, 0.08, z + 0.011), 0.045, Color(0.95, 0.92, 0.8))
	Props.words(s, "CORNER GROCERY", Vector3(0, 0.032, z + 0.011), 0.032, Color(0.95, 0.92, 0.8))
	if month != "":
		Props.words(s, month, Vector3(0, -0.03, z + 0.008), 0.034, Color(0.6, 0.12, 0.1))
	for r in 5:
		for c in 7:
			Kit.box(s, Vector3(0.036, 0.03, 0.004), Vector3(-0.15 + c * 0.05, -0.08 - r * 0.045, z + 0.006), Color(0.82, 0.8, 0.74))
	Kit.ring(s, 0.028, 0.006, Vector3(0.05, -0.17, z + 0.01), Color(0.8, 0.1, 0.1))
	return g


# ------------------------------------------------------------------- lamps

## A floor lamp with a pleated shade and a fringe, lit.
static func floor_lamp(p: Node3D, b: int, u: float, v: float, shade := Color(0.98, 0.88, 0.62), solid := true) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.42, 0.42, solid)
	Kit.cyl(g, 0.17, 0.05, Vector3(0, 0.025, 0), BRASS.darkened(0.25), Vector3.ZERO, 12)
	Kit.cyl(g, 0.02, 1.4, Vector3(0, 0.75, 0), BRASS, Vector3.ZERO, 6)
	Kit.ball(g, 0.04, Vector3(0, 0.8, 0), BRASS, 6)
	Kit.cyl(g, 0.25, 0.34, Vector3(0, 1.58, 0), Kit.flat(shade, 0.9), Vector3.ZERO, 14, 0.15)
	Kit.cyl(g, 0.255, 0.05, Vector3(0, 1.39, 0), shade.darkened(0.3), Vector3.ZERO, 14)      # the fringe
	Kit.omni(g, Vector3(0, 1.5, 0.15), Color(1.0, 0.78, 0.5), 0.7, 3.6)
	return g


## A table lamp: a china jar base and a shade, lit unless `light` is false.
static func table_lamp(parent: Node3D, pos: Vector3, base := Color(0.55, 0.72, 0.62), shade := Color(0.98, 0.9, 0.72), light := true) -> Node3D:
	var g := Kit.group(parent, pos)
	Kit.cyl(g, 0.07, 0.025, Vector3(0, 0.0125, 0), BRASS, Vector3.ZERO, 10)
	Kit.ball(g, 0.095, Vector3(0, 0.12, 0), base, 10)
	Kit.cyl(g, 0.014, 0.16, Vector3(0, 0.27, 0), BRASS, Vector3.ZERO, 5)
	Kit.cyl(g, 0.16, 0.22, Vector3(0, 0.42, 0), Kit.flat(shade, 0.85), Vector3.ZERO, 12, 0.095)
	if light:
		Kit.omni(g, Vector3(0, 0.38, 0.12), Color(1.0, 0.8, 0.55), 0.5, 2.6)
	return g


# ----------------------------------------------------------------- parlour

## The good sofa: rolled arms and a humped back, in its clear plastic cover,
## lace on the arms and over the back.
static func plastic_sofa(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 2.2, look := Color(0.78, 0.55, 0.3), d := 0.92) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	var arm := 0.24
	var inner := w - arm * 2.0
	for x: float in [-w * 0.5 + 0.1, w * 0.5 - 0.1]:
		for z: float in [-d * 0.5 + 0.1, d * 0.5 - 0.1]:
			Kit.ball(g, 0.05, Vector3(x, 0.05, z), Props.WOOD_DARK, 6)
	Kit.block(g, Vector3(inner + 0.02, 0.3, d - 0.08), Vector3(0, 0.08, 0.02), look.darkened(0.18))
	Kit.box(g, Vector3(inner, 0.035, 0.012), Vector3(0, 0.2, d * 0.5 - 0.013), Color(0.85, 0.7, 0.35))        # gold braid along the front
	var n := 3 if inner > 1.3 else 2
	var cw := inner / n
	for i in n:
		var x := -inner * 0.5 + (i + 0.5) * cw
		Kit.block(g, Vector3(cw - 0.03, 0.15, d - 0.34), Vector3(x, 0.38, 0.1), look)
		Kit.block(g, Vector3(cw - 0.01, 0.17, d - 0.32), Vector3(x, 0.375, 0.1), PLASTIC)       # the cover
		Kit.box(g, Vector3(cw - 0.14, 0.014, 0.014), Vector3(x, 0.535, d * 0.5 - 0.05), SHINE)
		for k in 2:     # roses on the cushion fronts
			Kit.disc(g, 0.035, Vector3(x - cw * 0.2 + k * cw * 0.4, 0.455, (d - 0.34) * 0.5 + 0.1 + 0.004), Color(0.75, 0.25, 0.25), 0.006, 8)
	# the back, humped in the middle, with its cover
	var bz := -d * 0.5 + 0.14
	Kit.block(g, Vector3(inner + 0.02, 0.6, 0.26), Vector3(0, 0.38, bz), look.darkened(0.06))
	Kit.cyl(g, 0.13, inner + 0.02, Vector3(0, 0.98, bz), look, Vector3(0, 0, 90), 10)
	Kit.cyl(g, 0.14, inner * 0.42, Vector3(0, 1.04, bz), look, Vector3(0, 0, 90), 10)
	Kit.cyl(g, 0.145, inner + 0.04, Vector3(0, 0.98, bz), PLASTIC, Vector3(0, 0, 90), 10)
	Kit.cyl(g, 0.155, inner * 0.42 + 0.02, Vector3(0, 1.04, bz), PLASTIC, Vector3(0, 0, 90), 10)
	Kit.box(g, Vector3(inner * 0.8, 0.014, 0.014), Vector3(0, 1.1, bz + 0.12), SHINE, Vector3(-30, 0, 0))
	drape(g, Vector3(0, 1.185, bz), 0.42, 0.165, 0.2)
	# rolled arms, covered, a doily on each
	for side: float in [-1.0, 1.0]:
		var x := side * (w * 0.5 - arm * 0.5)
		Kit.block(g, Vector3(arm, 0.5, d - 0.02), Vector3(x, 0.08, 0), look.darkened(0.04))
		Kit.cyl(g, 0.14, d, Vector3(x, 0.6, 0), look, Vector3(90, 0, 0), 10)
		Kit.cyl(g, 0.155, d + 0.02, Vector3(x, 0.6, 0), PLASTIC, Vector3(90, 0, 0), 10)
		Kit.box(g, Vector3(0.014, 0.014, d * 0.8), Vector3(x + side * 0.06, 0.73, 0), SHINE)
		doily(g, Vector3(x, 0.757, 0.12), 0.1)
	return g


## A wingback chair, with lace over its back.
static func wingback(p: Node3D, b: int, u: float, v: float, yaw := 0.0, look := Color(0.42, 0.5, 0.36)) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.8, 0.8)
	for x: float in [-0.3, 0.3]:
		for z: float in [-0.3, 0.3]:
			Kit.block(g, Vector3(0.05, 0.12, 0.05), Vector3(x, 0, z), Props.WOOD_DARK)
	Kit.block(g, Vector3(0.74, 0.3, 0.72), Vector3(0, 0.12, 0.02), look.darkened(0.12))
	Kit.block(g, Vector3(0.5, 0.12, 0.5), Vector3(0, 0.42, 0.08), look)
	Kit.block(g, Vector3(0.6, 0.78, 0.16), Vector3(0, 0.42, -0.3), look)
	for side: float in [-1.0, 1.0]:
		Kit.block(g, Vector3(0.12, 0.26, 0.6), Vector3(side * 0.31, 0.42, 0.08), look)
		Kit.cyl(g, 0.07, 0.6, Vector3(side * 0.31, 0.69, 0.08), look, Vector3(90, 0, 0), 8)
		Kit.box(g, Vector3(0.1, 0.5, 0.3), Vector3(side * 0.33, 0.98, -0.24), look.darkened(0.05), Vector3(0, side * -18.0, 0))     # the wings
	drape(g, Vector3(0, 1.2, -0.3), 0.36, 0.09, 0.18)
	return g


## An upright piano and its bench, the family in frames along the top. The
## floor space is the piano with the bench in front of it.
static func piano(p: Node3D, b: int, u: float, v: float, yaw := 0.0, look := MAHOGANY) -> Node3D:
	var w := 1.48
	var d := 1.05
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	var back := -d * 0.5 + 0.01
	Kit.block(g, Vector3(w, 1.3, 0.38), Vector3(0, 0, back + 0.19), look)                       # the case
	Kit.box(g, Vector3(w + 0.05, 0.05, 0.44), Vector3(0, 1.325, back + 0.2), look.darkened(0.25))   # the lid
	Kit.box(g, Vector3(w - 0.24, 0.42, 0.03), Vector3(0, 1.03, back + 0.39), look.lightened(0.08))  # the panel over the keys
	Kit.box(g, Vector3(w - 0.34, 0.5, 0.03), Vector3(0, 0.33, back + 0.39), look.lightened(0.05))   # and under them
	for x: float in [-0.35, 0.35]:
		Kit.cyl(g, 0.06, 0.03, Vector3(x, 1.03, back + 0.415), BRASS, Vector3(90, 0, 0), 10)        # candle sconces
	Kit.box(g, Vector3(0.46, 0.24, 0.012), Vector3(0, 1.0, back + 0.42), Props.PAPER, Vector3(-12, 0, 0))   # music on the stand
	Kit.box(g, Vector3(0.3, 0.012, 0.008), Vector3(-0.05, 1.03, back + 0.43), Props.DARK, Vector3(-12, 0, 0))
	Kit.box(g, Vector3(0.3, 0.012, 0.008), Vector3(-0.05, 0.97, back + 0.437), Props.DARK, Vector3(-12, 0, 0))
	Kit.block(g, Vector3(w - 0.03, 0.1, 0.3), Vector3(0, 0.64, back + 0.53), look)               # the key bed
	Kit.box(g, Vector3(w - 0.22, 0.03, 0.17), Vector3(0, 0.755, back + 0.6), Color(0.97, 0.96, 0.9))
	for i in 25:
		if i % 7 == 2 or i % 7 == 6:
			continue
		Kit.box(g, Vector3(0.026, 0.026, 0.1), Vector3(-0.63 + i * 0.0525, 0.78, back + 0.56), Props.DARK)
	for side: float in [-1.0, 1.0]:
		Kit.block(g, Vector3(0.11, 0.2, 0.34), Vector3(side * (w * 0.5 - 0.055), 0.62, back + 0.55), look.lightened(0.06))
		Kit.block(g, Vector3(0.08, 0.62, 0.08), Vector3(side * (w * 0.5 - 0.06), 0, back + 0.62), look)
	# the bench
	var bz := back + 0.86
	Kit.box(g, Vector3(0.86, 0.07, 0.36), Vector3(0, 0.5, bz), look)
	for x: float in [-0.36, 0.36]:
		for z: float in [-0.13, 0.13]:
			Kit.block(g, Vector3(0.05, 0.465, 0.05), Vector3(x, 0, bz + z), look.darkened(0.15))
	# along the top: a runner, a vase, the family
	runner(g, Vector3(0, 1.35, back + 0.2), w - 0.3, 0.26, 0.14)
	var sizes := [[0.15, 0.2], [0.2, 0.15], [0.13, 0.17], [0.17, 0.22], [0.14, 0.18], [0.2, 0.26]]
	var x0 := -w * 0.5 + 0.12
	for k in sizes.size():
		var s: Array = sizes[k]
		photo(g, Vector3(x0 + s[0] * 0.5, 1.356, back + 0.16 + 0.07 * (k % 2)), s[0], s[1], 12.0 * (Props.rnd(k * 4.1) - 0.5), u + k * 3.3)
		x0 += s[0] + 0.035
		if k == 2:
			x0 += 0.12        # room for the vase
	var vx := -w * 0.5 + 0.12 + 0.15 + 0.2 + 0.13 + 0.035 * 3 + 0.06
	Kit.cyl(g, 0.05, 0.18, Vector3(vx, 1.445, back + 0.2), Color(0.3, 0.45, 0.7), Vector3.ZERO, 10, 0.035)
	for k in 3:
		Kit.ball(g, 0.04, Vector3(vx - 0.04 + k * 0.04, 1.57 + 0.03 * (k % 2), back + 0.2), BLOOMS[k], 6)
	return g


## A console television: a long cabinet on short legs, the screen at one end
## and the speaker cloth at the other, lace and photographs on top.
static func console_tv(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.35) -> Node3D:
	var d := 0.5
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	var wood := WALNUT
	for x: float in [-w * 0.5 + 0.08, w * 0.5 - 0.08]:
		for z: float in [-d * 0.5 + 0.08, d * 0.5 - 0.08]:
			Kit.block(g, Vector3(0.05, 0.15, 0.05), Vector3(x, 0, z), Props.WOOD_DARK)
	Kit.block(g, Vector3(w, 0.66, d), Vector3(0, 0.15, 0), wood)
	Kit.box(g, Vector3(w + 0.03, 0.04, d + 0.03), Vector3(0, 0.83, 0), wood.darkened(0.15))
	var front := d * 0.5
	var sx := -w * 0.5 + 0.38
	Kit.box(g, Vector3(0.62, 0.5, 0.02), Vector3(sx, 0.49, front + 0.006), Props.DARK)
	Kit.box(g, Vector3(0.52, 0.4, 0.02), Vector3(sx, 0.49, front + 0.014), Kit.flat(Color(0.5, 0.68, 0.85), 0.9))
	Kit.box(g, Vector3(0.2, 0.04, 0.006), Vector3(sx - 0.08, 0.58, front + 0.026), Kit.flat(Color(0.9, 0.95, 1.0), 1.2))
	var cx := w * 0.5 - 0.3
	Kit.box(g, Vector3(0.46, 0.5, 0.02), Vector3(cx, 0.49, front + 0.006), Color(0.86, 0.76, 0.52))
	for k in 6:
		Kit.box(g, Vector3(0.026, 0.5, 0.02), Vector3(cx - 0.2 + k * 0.08, 0.49, front + 0.016), wood.darkened(0.1))
	for x: float in [cx - 0.12, cx + 0.12]:
		Kit.cyl(g, 0.04, 0.03, Vector3(x, 0.22, front + 0.01), BRASS, Vector3(90, 0, 0), 10)
	runner(g, Vector3(0, 0.85, 0), w * 0.72, d * 0.62, 0.12)
	Kit.cyl(g, 0.04, 0.05, Vector3(-w * 0.5 + 0.2, 0.88, -0.08), Props.DARK, Vector3.ZERO, 8)     # rabbit ears
	Kit.cyl(g, 0.006, 0.55, Vector3(-w * 0.5 + 0.2 - 0.1, 1.12, -0.08), Props.STEEL, Vector3(0, 0, 25), 4)
	Kit.cyl(g, 0.006, 0.55, Vector3(-w * 0.5 + 0.2 + 0.1, 1.12, -0.08), Props.STEEL, Vector3(0, 0, -25), 4)
	photo(g, Vector3(0.0, 0.856, -0.05), 0.18, 0.23, -6.0, u * 1.7)
	photo(g, Vector3(0.28, 0.856, -0.02), 0.15, 0.19, 8.0, u * 2.9)
	Kit.cyl(g, 0.09, 0.05, Vector3(w * 0.5 - 0.16, 0.88, 0.05), Color(0.6, 0.78, 0.7, 0.8), Vector3.ZERO, 10, 0.11)   # the candy dish
	for k in 4:
		Kit.ball(g, 0.022, Vector3(w * 0.5 - 0.2 + k * 0.025, 0.91, 0.04 + 0.02 * (k % 2)), BLOOMS[k], 5)
	return g


## A plant stand with a big Boston fern.
static func fern_stand(p: Node3D, b: int, u: float, v: float, size := 1.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.5, 0.5)
	Kit.cyl(g, 0.16, 0.04, Vector3(0, 0.02, 0), Props.WOOD_DARK, Vector3.ZERO, 10)
	Kit.cyl(g, 0.04, 0.7, Vector3(0, 0.37, 0), Props.WOOD_DARK, Vector3.ZERO, 8)
	Kit.cyl(g, 0.17, 0.04, Vector3(0, 0.74, 0), Props.WOOD_DARK, Vector3.ZERO, 10)
	fern(g, Vector3(0, 0.76, 0), size)
	return g


## A fern in a pot: fronds out all round and drooping.
static func fern(parent: Node3D, pos: Vector3, size := 1.0) -> void:
	Kit.cyl(parent, 0.13 * size, 0.2 * size, pos + Vector3(0, 0.1 * size, 0), Color(0.72, 0.42, 0.28), Vector3.ZERO, 10, 0.16 * size)
	Kit.ball(parent, 0.15 * size, pos + Vector3(0, 0.22 * size, 0), LEAF.darkened(0.15), 8)
	for i in 12:
		var a := 30.0 * i + 13.0 * Props.rnd(i * 1.7)
		var arm := Kit.group(parent, pos + Vector3(0, 0.22 * size, 0), Vector3(0, a, 0))
		var tip := Kit.group(arm, Vector3.ZERO, Vector3(-35.0 - 30.0 * Props.rnd(i * 3.1), 0, 0))
		Kit.box(tip, Vector3(0.1 * size, 0.02, 0.42 * size), Vector3(0, 0, 0.2 * size), LEAF.lightened(0.12 * (i % 2)))


# ------------------------------------------------------------------ dining

## A china cabinet: a closed base, glass doors over two shelves of her good
## plates stood on edge, the cups in front of them.
static func china_cabinet(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.3) -> Node3D:
	var d := 0.48
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	var wood := MAHOGANY
	Kit.block(g, Vector3(w, 0.86, d), Vector3.ZERO, wood)
	for x: float in [-w * 0.25, w * 0.25]:
		Kit.box(g, Vector3(w * 0.5 - 0.08, 0.5, 0.02), Vector3(x, 0.33, d * 0.5 + 0.01), wood.lightened(0.08))
		Kit.ball(g, 0.022, Vector3(x * 0.25, 0.42, d * 0.5 + 0.03), BRASS, 6)
	Kit.box(g, Vector3(w - 0.08, 0.14, 0.02), Vector3(0, 0.71, d * 0.5 + 0.01), wood.lightened(0.08))
	Kit.box(g, Vector3(w + 0.04, 0.04, d + 0.04), Vector3(0, 0.88, 0), wood.darkened(0.15))
	runner(g, Vector3(0, 0.9, 0.19), w * 0.7, 0.12, 0.08)
	var hd := 0.36
	var hz := -d * 0.5 + hd * 0.5
	Kit.box(g, Vector3(w - 0.08, 1.12, 0.02), Vector3(0, 1.46, -d * 0.5 + 0.03), Color(0.72, 0.62, 0.55))    # the lining
	Kit.box(g, Vector3(w, 1.14, 0.02), Vector3(0, 1.47, -d * 0.5 + 0.01), wood)
	for side: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(0.05, 1.14, hd), Vector3(side * (w * 0.5 - 0.025), 1.47, hz), wood)
	Kit.box(g, Vector3(w + 0.08, 0.08, hd + 0.08), Vector3(0, 2.07, hz + 0.02), wood.darkened(0.15))
	Kit.box(g, Vector3(w * 0.4, 0.1, 0.03), Vector3(0, 2.15, hz + hd * 0.5 + 0.02), wood.darkened(0.1))
	var plate := Color(0.97, 0.96, 0.92)
	var rim := Color(0.25, 0.4, 0.75)
	for shelf in 2:
		var y := 1.0 + shelf * 0.5
		Kit.box(g, Vector3(w - 0.1, 0.02, hd - 0.04), Vector3(0, y, hz - 0.01), wood.lightened(0.1))
		for k in 4:
			var x := -w * 0.5 + 0.2 + k * (w - 0.4) / 3.0
			Kit.cyl(g, 0.15, 0.012, Vector3(x, y + 0.165, -d * 0.5 + 0.08), rim, Vector3(76, 0, 0), 16)
			Kit.cyl(g, 0.11, 0.012, Vector3(x, y + 0.165, -d * 0.5 + 0.084), plate, Vector3(76, 0, 0), 16)
		for k in 3:
			var x := -w * 0.5 + 0.33 + k * (w - 0.66) / 2.0
			Kit.cyl(g, 0.045, 0.07, Vector3(x, y + 0.045, hz + 0.08), plate, Vector3.ZERO, 10, 0.055)
			Kit.cyl(g, 0.07, 0.008, Vector3(x, y + 0.014, hz + 0.08), rim, Vector3.ZERO, 12)
	Kit.box(g, Vector3(w - 0.1, 1.06, 0.012), Vector3(0, 1.47, -d * 0.5 + hd + 0.006), Color(0.8, 0.9, 0.95, 0.22))
	for x: float in [-w * 0.25, 0.0, w * 0.25]:
		Kit.box(g, Vector3(0.03, 1.06, 0.02), Vector3(x, 1.47, -d * 0.5 + hd + 0.012), wood)
	Kit.box(g, Vector3(w - 0.1, 0.03, 0.02), Vector3(0, 1.47, -d * 0.5 + hd + 0.012), wood)
	return g


## A dining table under a lace cloth that hangs over its edges.
static func lace_table(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.4, d := 0.85, look := MAHOGANY) -> Node3D:
	var g := Props.table(p, b, u, v, yaw, w, d, look)
	Kit.box(g, Vector3(w + 0.1, 0.008, d + 0.1), Vector3(0, 0.744, 0), LACE)
	for side: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(w + 0.1, 0.16, 0.008), Vector3(0, 0.67, side * (d * 0.5 + 0.054)), LACE)
		Kit.box(g, Vector3(0.008, 0.16, d + 0.1), Vector3(side * (w * 0.5 + 0.054), 0.67, 0), LACE)
		for k in int(w / 0.09):
			Kit.cyl(g, 0.045, 0.008, Vector3(-w * 0.5 - 0.05 + (k + 0.5) * (w + 0.1) / int(w / 0.09), 0.59, side * (d * 0.5 + 0.054)), LACE, Vector3(90, 0, 0), 8)
	return g


## A bowl of fruit, to stand on a table or a sideboard.
static func fruit_bowl(parent: Node3D, pos: Vector3) -> void:
	Kit.cyl(parent, 0.16, 0.08, pos + Vector3(0, 0.05, 0), Color(0.75, 0.82, 0.86, 0.7), Vector3.ZERO, 12, 0.19)
	Kit.cyl(parent, 0.07, 0.02, pos + Vector3(0, 0.01, 0), Color(0.75, 0.82, 0.86, 0.7), Vector3.ZERO, 10)
	var fruit := [Color(0.85, 0.15, 0.12), Color(0.98, 0.75, 0.1), Color(0.95, 0.55, 0.1), Color(0.45, 0.7, 0.2), Color(0.5, 0.2, 0.45)]
	for k in 7:
		var a := TAU * k / 7.0
		var r := 0.09 if k < 6 else 0.0
		Kit.ball(parent, 0.055, pos + Vector3(cos(a) * r, 0.12 + (0.05 if k == 6 else 0.0), sin(a) * r), fruit[k % fruit.size()], 7)
	Kit.box(parent, Vector3(0.05, 0.03, 0.22), pos + Vector3(0.02, 0.2, 0.0), Color(0.98, 0.85, 0.2), Vector3(0, 30, 50))     # the bananas


## A candlestick, to stand on something.
static func candlestick(parent: Node3D, pos: Vector3) -> void:
	Kit.cyl(parent, 0.05, 0.02, pos + Vector3(0, 0.01, 0), BRASS, Vector3.ZERO, 10)
	Kit.cyl(parent, 0.015, 0.2, pos + Vector3(0, 0.12, 0), BRASS, Vector3.ZERO, 6)
	Kit.cyl(parent, 0.016, 0.16, pos + Vector3(0, 0.3, 0), Color(0.96, 0.94, 0.85), Vector3.ZERO, 6)


# ------------------------------------------------------------------ the hall

## A church hat: a wide brim, a crown, a band and a flower.
static func church_hat(parent: Node3D, pos: Vector3, look: Color, trim: Color, tilt := Vector3.ZERO, brim := 0.2) -> Node3D:
	var h := Kit.group(parent, pos, tilt)
	Kit.cyl(h, brim, 0.018, Vector3.ZERO, look, Vector3.ZERO, 16)
	Kit.cyl(h, brim * 0.52, 0.12, Vector3(0, 0.065, 0), look.darkened(0.06), Vector3.ZERO, 14, brim * 0.46)
	Kit.cyl(h, brim * 0.54, 0.035, Vector3(0, 0.03, 0), trim, Vector3.ZERO, 14)
	Kit.ball(h, 0.05, Vector3(brim * 0.5, 0.06, brim * 0.12), trim.lightened(0.15), 8)
	Kit.ball(h, 0.035, Vector3(brim * 0.56, 0.05, brim * 0.3), trim.lightened(0.35), 6)
	return h


## A hall stand with her church hats on its pegs, and a hat box at its foot.
static func hat_stand(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.7, 0.62)
	var wood := Props.WOOD_DARK
	for a: float in [45.0, 135.0]:
		Kit.box(g, Vector3(0.6, 0.05, 0.07), Vector3(0, 0.025, 0), wood, Vector3(0, a, 0))
	Kit.cyl(g, 0.035, 1.82, Vector3(0, 0.93, 0), wood, Vector3.ZERO, 8)
	Kit.ball(g, 0.06, Vector3(0, 1.86, 0), wood, 8)
	var hats := [
		[SUNDAY[0], Color(0.95, 0.85, 0.3), 1.72, 30.0],
		[SUNDAY[2], Color(0.1, 0.1, 0.12), 1.58, 150.0],
		[SUNDAY[1], Color(0.98, 0.95, 0.9), 1.66, 270.0],
		[SUNDAY[4], Color(0.55, 0.2, 0.6), 1.45, 90.0],
		[SUNDAY[3], Color(0.95, 0.95, 0.92), 1.4, 210.0],
	]
	for hat: Array in hats:
		var a := deg_to_rad(hat[3])
		var out := Vector3(sin(a), 0, cos(a))
		Kit.box(g, Vector3(0.025, 0.025, 0.16), Vector3(0, hat[2], 0) + out * 0.08, wood, Vector3(0, hat[3], 0))
		church_hat(g, Vector3(0, hat[2] - 0.02, 0) + out * 0.2, hat[0], hat[1], Vector3(25, hat[3], 0), 0.2)
	var box := Kit.group(g, Vector3(0.18, 0, 0.2))
	Kit.cyl(box, 0.17, 0.24, Vector3(0, 0.12, 0), Color(0.95, 0.88, 0.85), Vector3.ZERO, 14)
	for k in 3:
		Kit.cyl(box, 0.172, 0.025, Vector3(0, 0.04 + k * 0.07, 0), Color(0.6, 0.3, 0.55), Vector3.ZERO, 14)
	Kit.cyl(box, 0.18, 0.04, Vector3(0, 0.26, 0), Color(0.6, 0.3, 0.55), Vector3.ZERO, 14)
	return g


## A gossip bench: a padded seat with the telephone table built on, the phone
## and the book on it.
static func gossip_bench(p: Node3D, b: int, u: float, v: float, yaw := 0.0, look := WALNUT, pad := Color(0.7, 0.2, 0.25)) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.05, 0.45)
	for x: float in [-0.48, 0.0, 0.48]:
		for z: float in [-0.18, 0.18]:
			Kit.block(g, Vector3(0.04, 0.44, 0.04), Vector3(x, 0, z), look.darkened(0.15))
	Kit.box(g, Vector3(0.5, 0.1, 0.42), Vector3(-0.25, 0.47, 0), pad)                # the seat
	Kit.box(g, Vector3(0.5, 0.36, 0.05), Vector3(-0.25, 0.7, -0.19), pad)
	Kit.box(g, Vector3(0.04, 0.2, 0.42), Vector3(-0.5, 0.6, 0), look)
	Kit.box(g, Vector3(0.5, 0.04, 0.42), Vector3(0.25, 0.72, 0), look)               # the table
	Kit.box(g, Vector3(0.46, 0.03, 0.38), Vector3(0.25, 0.3, 0), look)
	Kit.block(g, Vector3(0.28, 0.06, 0.2), Vector3(0.25, 0.32, 0), Color(0.9, 0.85, 0.3))   # the book
	doily(g, Vector3(0.25, 0.74, 0.0), 0.13)
	Kit.block(g, Vector3(0.2, 0.09, 0.2), Vector3(0.25, 0.75, 0.0), Color(0.15, 0.15, 0.17))    # the phone
	Kit.disc(g, 0.06, Vector3(0.25, 0.83, 0.07), Color(0.88, 0.86, 0.8), 0.01, 10)
	Kit.box(g, Vector3(0.26, 0.05, 0.06), Vector3(0.25, 0.87, -0.04), Color(0.15, 0.15, 0.17))
	for x: float in [0.14, 0.36]:
		Kit.ball(g, 0.035, Vector3(x, 0.87, -0.04), Color(0.15, 0.15, 0.17), 6)
	return g


# ----------------------------------------------------------------- kitchen

## Her big pot on a burner, a lid on it, steam coming off.
static func stockpot(parent: Node3D, pos: Vector3, look := Color(0.25, 0.35, 0.6)) -> void:
	Kit.cyl(parent, 0.17, 0.3, pos + Vector3(0, 0.15, 0), look, Vector3.ZERO, 14)
	for k in 6:
		Kit.ball(parent, 0.012, pos + Vector3(cos(k * 1.1) * 0.172, 0.08 + 0.03 * (k % 3), sin(k * 1.1) * 0.172), Color(0.9, 0.9, 0.92), 4)
	Kit.cyl(parent, 0.18, 0.02, pos + Vector3(0, 0.31, 0), look.darkened(0.1), Vector3.ZERO, 14)
	Kit.ball(parent, 0.03, pos + Vector3(0, 0.34, 0), Props.DARK, 6)
	for side: float in [-1.0, 1.0]:
		Kit.box(parent, Vector3(0.06, 0.03, 0.05), pos + Vector3(side * 0.2, 0.26, 0), Props.DARK)
	for k in 3:
		Kit.ball(parent, 0.06 + 0.02 * k, pos + Vector3(0.04 * k - 0.04, 0.45 + 0.13 * k, -0.02 * k), Color(1, 1, 1, 0.35 - 0.08 * k), 7)


## A pie with a lattice top, in its tin.
static func pie(parent: Node3D, pos: Vector3) -> void:
	Kit.cyl(parent, 0.15, 0.03, pos + Vector3(0, 0.015, 0), Color(0.7, 0.72, 0.74), Vector3.ZERO, 14, 0.17)
	Kit.cyl(parent, 0.165, 0.05, pos + Vector3(0, 0.045, 0), Color(0.88, 0.62, 0.3), Vector3.ZERO, 14)
	Kit.cyl(parent, 0.14, 0.01, pos + Vector3(0, 0.072, 0), Color(0.55, 0.2, 0.18), Vector3.ZERO, 14)    # the filling, through the lattice
	for k in 4:
		var o := -0.09 + k * 0.06
		Kit.box(parent, Vector3(0.025, 0.014, 0.27 - absf(o)), pos + Vector3(o, 0.08, 0), Color(0.93, 0.7, 0.38))
		Kit.box(parent, Vector3(0.27 - absf(o), 0.014, 0.025), pos + Vector3(0, 0.084, o), Color(0.95, 0.73, 0.4))


## A small kitchen table under a red and white check oilcloth.
static func kitchen_table(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 0.95, d := 0.75) -> Node3D:
	var g := Props.table(p, b, u, v, yaw, w, d, Color(0.85, 0.85, 0.82))
	var check := Kit.tex("lino", 0.24, Color(0.9, 0.5, 0.5), false, Color(1.0, 0.45, 0.42))
	Kit.box(g, Vector3(w + 0.08, 0.01, d + 0.08), Vector3(0, 0.745, 0), check)
	for side: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(w + 0.08, 0.12, 0.01), Vector3(0, 0.69, side * (d * 0.5 + 0.045)), check)
		Kit.box(g, Vector3(0.01, 0.12, d + 0.08), Vector3(side * (w * 0.5 + 0.045), 0.69, 0), check)
	return g


## Cupboards on the wall over the worktops.
static func wall_cupboards(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.6, look := Color(0.93, 0.92, 0.85)) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.36, false)
	Kit.box(g, Vector3(w, 0.72, 0.34), Vector3(0, 1.88, 0.18), look)
	var n := maxi(int(round(w / 0.45)), 1)
	for i in n:
		var x := -w * 0.5 + (i + 0.5) * w / n
		Kit.box(g, Vector3(w / n - 0.05, 0.64, 0.02), Vector3(x, 1.88, 0.355), look.darkened(0.05))
		Kit.box(g, Vector3(0.02, 0.1, 0.03), Vector3(x + (w / n * 0.5 - 0.07) * (1.0 if i % 2 == 0 else -1.0), 1.68, 0.375), Color(0.75, 0.15, 0.12))
	return g


## A row of canisters, to stand on a worktop.
static func canisters(parent: Node3D, pos: Vector3) -> void:
	for k in 4:
		var r := 0.085 - k * 0.012
		Kit.cyl(parent, r, 0.26 - k * 0.04, pos + Vector3(k * 0.17, (0.26 - k * 0.04) * 0.5, 0), Color(0.92, 0.9, 0.85), Vector3.ZERO, 10)
		Kit.cyl(parent, r + 0.004, 0.03, pos + Vector3(k * 0.17, 0.26 - k * 0.04, 0), Color(0.75, 0.15, 0.12), Vector3.ZERO, 10)
		Kit.box(parent, Vector3(r * 1.1, 0.03, 0.006), pos + Vector3(k * 0.17, 0.12, r), Color(0.75, 0.15, 0.12))


## A dish rack with plates in it, to stand on a worktop.
static func dish_rack(parent: Node3D, pos: Vector3) -> void:
	Kit.box(parent, Vector3(0.4, 0.03, 0.3), pos + Vector3(0, 0.015, 0), Color(0.85, 0.85, 0.88))
	for k in 5:
		Kit.cyl(parent, 0.11, 0.012, pos + Vector3(-0.15 + k * 0.07, 0.13, 0), Color(0.96, 0.96, 0.94), Vector3(0, 0, 80), 12)


# ------------------------------------------------------------------ sun room

## A wicker armchair with a round fan back and a flowered cushion.
static func wicker_chair(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 0.75, pad := Color(0.35, 0.6, 0.45)) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.72)
	var cane := Color(0.82, 0.68, 0.45)
	Kit.block(g, Vector3(w - 0.06, 0.4, 0.6), Vector3(0, 0, 0.04), cane.darkened(0.12))
	for k in 4:
		Kit.box(g, Vector3(w - 0.05, 0.02, 0.61), Vector3(0, 0.08 + k * 0.09, 0.04), cane.lightened(0.1))
	Kit.block(g, Vector3(w - 0.14, 0.1, 0.52), Vector3(0, 0.4, 0.08), pad)
	var back := Kit.cyl(g, w * 0.55, 0.08, Vector3(0, 0.82, -0.28), cane, Vector3(90, 0, 0), 16)
	back.scale = Vector3(1, 1, 1.15)
	for k in 3:
		Kit.ring(g, w * 0.18 + k * w * 0.11, 0.015, Vector3(0, 0.78, -0.235), cane.darkened(0.2))
	for side: float in [-1.0, 1.0]:
		Kit.block(g, Vector3(0.1, 0.62, 0.62), Vector3(side * (w * 0.5 - 0.05), 0, 0.025), cane)
		Kit.cyl(g, 0.065, 0.62, Vector3(side * (w * 0.5 - 0.05), 0.63, 0.03), cane.lightened(0.05), Vector3(90, 0, 0), 8)
	for k in 3:
		Kit.disc(g, 0.04, Vector3(-0.15 + k * 0.15, 0.48, 0.345), BLOOMS[k], 0.008, 8)
	return g


## A tiered stand of African violets.
static func violets(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.8, 0.45)
	var wood := WHITE.darkened(0.08)
	for k in 3:
		var z := -0.12 + k * 0.12
		var y := 0.85 - k * 0.3
		Kit.box(g, Vector3(0.78, 0.03, 0.14), Vector3(0, y, z), wood)
		for i in 3:
			var x := -0.24 + i * 0.24
			Kit.cyl(g, 0.055, 0.08, Vector3(x, y + 0.055, z), Color(0.75, 0.45, 0.32), Vector3.ZERO, 8, 0.065)
			Kit.ball(g, 0.09, Vector3(x, y + 0.13, z), LEAF.darkened(0.1), 8)
			for f in 3:
				Kit.ball(g, 0.03, Vector3(x - 0.04 + f * 0.04, y + 0.2, z + 0.03 * (f % 2)), _pick([Color(0.6, 0.3, 0.85), Color(0.95, 0.45, 0.7), Color(0.98, 0.96, 0.95)], u + k * 3.0 + i), 6)
	for x: float in [-0.38, 0.38]:
		Kit.box(g, Vector3(0.03, 0.9, 0.03), Vector3(x, 0.45, 0.12), wood, Vector3(-17, 0, 0))
		Kit.box(g, Vector3(0.03, 0.9, 0.03), Vector3(x, 0.45, -0.1), wood)
	return g


## A big rubber plant in a tub on the floor.
static func rubber_plant(p: Node3D, b: int, u: float, v: float, size := 1.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.5 * size, 0.5 * size)
	Kit.cyl(g, 0.2 * size, 0.36 * size, Vector3(0, 0.18 * size, 0), Color(0.75, 0.42, 0.26), Vector3.ZERO, 10, 0.24 * size)
	Kit.cyl(g, 0.02, 1.3 * size, Vector3(0, 0.95 * size, 0), Color(0.35, 0.28, 0.15), Vector3.ZERO, 5)
	for i in 11:
		var a := 137.0 * i
		var y := (0.6 + i * 0.1) * size
		var leaf := Kit.group(g, Vector3(0, y, 0), Vector3(0, a, 0))
		Kit.box(leaf, Vector3(0.14 * size, 0.02, 0.32 * size), Vector3(0, 0.03, 0.16 * size), LEAF.darkened(0.25 * (i % 2)), Vector3(-25.0 + 10.0 * (i % 3), 0, 0))
	return g


## A bird cage on a stand, a yellow canary on the perch.
static func bird_cage(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.45, 0.45)
	Kit.cyl(g, 0.18, 0.03, Vector3(0, 0.015, 0), BRASS.darkened(0.2), Vector3.ZERO, 10)
	Kit.cyl(g, 0.02, 1.2, Vector3(0, 0.6, 0), BRASS, Vector3.ZERO, 6)
	Kit.cyl(g, 0.17, 0.03, Vector3(0, 1.21, 0), BRASS, Vector3.ZERO, 14)
	for k in 12:
		var a := TAU * k / 12.0
		Kit.cyl(g, 0.005, 0.45, Vector3(cos(a) * 0.16, 1.45, sin(a) * 0.16), BRASS, Vector3.ZERO, 4)
	Kit.cyl(g, 0.165, 0.02, Vector3(0, 1.68, 0), BRASS, Vector3.ZERO, 14)
	var dome := Kit.ball(g, 0.165, Vector3(0, 1.68, 0), Color(0.82, 0.66, 0.28, 0.35), 10)
	dome.scale = Vector3(1, 0.6, 1)
	Kit.ring(g, 0.05, 0.012, Vector3(0, 1.82, 0), BRASS)
	Kit.cyl(g, 0.006, 0.28, Vector3(0, 1.38, 0), Props.WOOD, Vector3(0, 0, 90), 4)       # the perch
	Kit.ball(g, 0.045, Vector3(0.02, 1.43, 0), Color(1.0, 0.85, 0.15), 8)
	Kit.ball(g, 0.03, Vector3(0.06, 1.48, 0), Color(1.0, 0.88, 0.2), 8)
	Kit.box(g, Vector3(0.07, 0.015, 0.03), Vector3(-0.04, 1.42, 0), Color(0.95, 0.8, 0.1), Vector3(0, 0, -25))
	Kit.box(g, Vector3(0.02, 0.012, 0.012), Vector3(0.095, 1.48, 0), Color(0.95, 0.55, 0.2))
	return g


## A round wicker side table with her Bible, her glasses and the radio.
static func radio_table(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.55, 0.55)
	var cane := Color(0.82, 0.68, 0.45)
	Kit.cyl(g, 0.22, 0.5, Vector3(0, 0.29, 0), cane.darkened(0.12), Vector3.ZERO, 12, 0.14)
	Kit.cyl(g, 0.27, 0.04, Vector3(0, 0.56, 0), cane, Vector3.ZERO, 14)
	doily(g, Vector3(0, 0.58, 0), 0.18)
	Kit.block(g, Vector3(0.28, 0.16, 0.14), Vector3(0.0, 0.59, -0.08), Color(0.55, 0.32, 0.2))     # the radio
	Kit.box(g, Vector3(0.14, 0.1, 0.01), Vector3(-0.05, 0.67, -0.008), Color(0.85, 0.75, 0.5))
	Kit.cyl(g, 0.025, 0.02, Vector3(0.09, 0.67, -0.005), BRASS, Vector3(90, 0, 0), 8)
	Kit.block(g, Vector3(0.18, 0.05, 0.24), Vector3(0.0, 0.59, 0.12), Color(0.12, 0.1, 0.1), Vector3(0, 15, 0))     # the Bible
	Kit.box(g, Vector3(0.12, 0.004, 0.016), Vector3(0.0, 0.645, 0.12), Color(0.85, 0.7, 0.3), Vector3(0, 15, 0))
	return g


# ------------------------------------------------------------------- pantry

## Shelves of home-canned jars: peaches, beans, beets, tomatoes, pickles.
static func preserves(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 2.0, h := 1.9) -> Node3D:
	var d := 0.36
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	var wood := Color(0.62, 0.46, 0.3)
	for x: float in [-w * 0.5 + 0.02, w * 0.5 - 0.02]:
		Kit.block(g, Vector3(0.04, h, d), Vector3(x, 0, 0), wood)
	var fill := [Color(0.98, 0.62, 0.2), Color(0.35, 0.6, 0.25), Color(0.62, 0.1, 0.25), Color(0.9, 0.25, 0.15), Color(0.6, 0.65, 0.25), Color(0.75, 0.35, 0.55)]
	for i in 5:
		var y := 0.08 + i * (h - 0.12) / 4.0
		Kit.box(g, Vector3(w - 0.08, 0.03, d - 0.02), Vector3(0, y, 0), wood.lightened(0.1))
		if i == 4:
			continue
		var x := -w * 0.5 + 0.12
		var n := 0
		while x < w * 0.5 - 0.1:
			var key := u * 3.3 + v * 1.7 + i * 7.1 + n * 1.3
			var c := _pick(fill, key)
			var jh := 0.17 + 0.05 * Props.rnd(key + 2.0)
			Kit.cyl(g, 0.055, jh, Vector3(x, y + 0.015 + jh * 0.5, 0.04), Color(0.85, 0.92, 0.95, 0.45), Vector3.ZERO, 8)
			Kit.cyl(g, 0.048, jh * 0.85, Vector3(x, y + 0.015 + jh * 0.43, 0.04), c, Vector3.ZERO, 8)
			Kit.cyl(g, 0.05, 0.025, Vector3(x, y + 0.03 + jh, 0.04), BRASS.lightened(0.1), Vector3.ZERO, 8)
			x += 0.135
			n += 1
	return g


## An old wringer washing machine: the tub on legs, the rollers on a post.
static func wringer(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.7, 0.7)
	var white := Color(0.92, 0.92, 0.88)
	for k in 4:
		var a := TAU * k / 4.0 + 0.78
		Kit.cyl(g, 0.025, 0.3, Vector3(cos(a) * 0.24, 0.15, sin(a) * 0.24), Props.STEEL, Vector3.ZERO, 5)
	Kit.cyl(g, 0.3, 0.62, Vector3(0, 0.6, 0), white, Vector3.ZERO, 14, 0.32)
	Kit.cyl(g, 0.32, 0.03, Vector3(0, 0.91, 0), Props.STEEL, Vector3.ZERO, 14)
	Kit.cyl(g, 0.29, 0.02, Vector3(0, 0.922, 0), Color(0.6, 0.72, 0.8), Vector3.ZERO, 14)
	Kit.box(g, Vector3(0.05, 0.5, 0.05), Vector3(0.0, 1.15, -0.26), Props.STEEL)
	Kit.box(g, Vector3(0.5, 0.12, 0.14), Vector3(0.0, 1.38, -0.26), Props.STEEL)
	for y: float in [1.35, 1.43]:
		Kit.cyl(g, 0.04, 0.44, Vector3(0, y, -0.18), Color(0.85, 0.85, 0.82), Vector3(0, 0, 90), 8)
	Kit.box(g, Vector3(0.03, 0.03, 0.22), Vector3(0.26, 1.39, -0.12), Props.DARK)
	return g


## A broom and a mop leaning in a corner, a bucket by them.
static func mops(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.5, 0.4)
	Kit.cyl(g, 0.014, 1.3, Vector3(-0.12, 0.7, -0.08), Props.WOOD, Vector3(-10, 0, 8), 5)
	Kit.box(g, Vector3(0.24, 0.24, 0.05), Vector3(-0.08, 0.12, 0.04), Color(0.85, 0.72, 0.35), Vector3(-10, 0, 8))
	Kit.cyl(g, 0.014, 1.25, Vector3(0.05, 0.68, -0.08), Props.WOOD, Vector3(-8, 0, -6), 5)
	Kit.cyl(g, 0.08, 0.16, Vector3(0.09, 0.08, -0.04), Color(0.85, 0.85, 0.8), Vector3.ZERO, 8)
	Kit.cyl(g, 0.13, 0.26, Vector3(0.12, 0.13, 0.08), Color(0.6, 0.62, 0.66), Vector3.ZERO, 10, 0.15)
	return g


# ------------------------------------------------------------------ bedroom

## A bed with a carved head and foot, two lace-edged pillows, and a patchwork
## quilt that hangs down its sides. The head is at the back of its floor space.
static func quilt_bed(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.5, l := 2.05, look := MAHOGANY, key := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, l)
	var head := -l * 0.5
	Kit.box(g, Vector3(w, 1.15, 0.06), Vector3(0, 0.575, head + 0.03), look)                    # the headboard
	Kit.cyl(g, w * 0.28, 0.06, Vector3(0, 1.15, head + 0.03), look, Vector3(90, 0, 0), 14)
	for side: float in [-1.0, 1.0]:
		Kit.block(g, Vector3(0.08, 1.25, 0.08), Vector3(side * (w * 0.5 - 0.02), 0, head + 0.03), look.darkened(0.15))
		Kit.ball(g, 0.06, Vector3(side * (w * 0.5 - 0.02), 1.3, head + 0.03), look.darkened(0.15), 8)
		Kit.block(g, Vector3(0.08, 0.8, 0.08), Vector3(side * (w * 0.5 - 0.02), 0, l * 0.5 - 0.04), look.darkened(0.15))
		Kit.ball(g, 0.055, Vector3(side * (w * 0.5 - 0.02), 0.84, l * 0.5 - 0.04), look.darkened(0.15), 8)
	Kit.box(g, Vector3(w - 0.12, 0.62, 0.05), Vector3(0, 0.45, l * 0.5 - 0.04), look)           # the footboard
	Kit.block(g, Vector3(w - 0.1, 0.32, l - 0.14), Vector3(0, 0.12, 0.0), Color(0.93, 0.92, 0.87))   # the mattress
	for x: float in [-w * 0.24, w * 0.24]:
		Kit.box(g, Vector3(w * 0.42, 0.14, 0.38), Vector3(x, 0.52, head + 0.3), Color(0.97, 0.96, 0.93), Vector3(-12, 0, 0))
		Kit.box(g, Vector3(w * 0.42 + 0.04, 0.03, 0.02), Vector3(x, 0.47, head + 0.5), LACE.darkened(0.04))
	# the quilt: patchwork squares over the top, down the sides and the foot
	var cols := [Color(0.82, 0.2, 0.22), Color(0.98, 0.8, 0.3), Color(0.25, 0.45, 0.75), Color(0.96, 0.94, 0.86), Color(0.3, 0.6, 0.4), Color(0.88, 0.5, 0.65), Color(0.55, 0.3, 0.6)]
	var nx := 5
	var top_z0 := head + 0.55
	var top_l := l * 0.5 - 0.07 - top_z0
	var nz := maxi(int(round(top_l / (w / nx))), 3)
	var sq := Vector2((w - 0.06) / nx, top_l / nz)
	for i in nx:
		for k in nz:
			var c: Color = cols[(i * 3 + k * 2 + int(key)) % cols.size()]
			Kit.box(g, Vector3(sq.x, 0.03, sq.y), Vector3(-w * 0.5 + 0.03 + (i + 0.5) * sq.x, 0.455, top_z0 + (k + 0.5) * sq.y), c)
	Kit.box(g, Vector3(w - 0.06, 0.08, 0.22), Vector3(0, 0.47, top_z0 - 0.05), Color(0.96, 0.94, 0.86))     # turned down at the top
	for side: float in [-1.0, 1.0]:
		for k in nz:
			var c: Color = cols[(k * 2 + (1 if side > 0 else 4) + int(key)) % cols.size()]
			Kit.box(g, Vector3(0.02, 0.3, sq.y), Vector3(side * (w * 0.5 - 0.02), 0.32, top_z0 + (k + 0.5) * sq.y), c)
	return g


## A night table with a lamp, her Bible and her glasses.
static func nightstand(p: Node3D, b: int, u: float, v: float, yaw := 0.0, light := true) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.46, 0.42)
	Kit.block(g, Vector3(0.46, 0.62, 0.42), Vector3.ZERO, MAHOGANY)
	Kit.box(g, Vector3(0.38, 0.14, 0.02), Vector3(0, 0.48, 0.215), MAHOGANY.lightened(0.1))
	Kit.ball(g, 0.02, Vector3(0, 0.48, 0.235), BRASS, 6)
	doily(g, Vector3(0, 0.62, 0), 0.16)
	table_lamp(g, Vector3(-0.06, 0.63, -0.04), Color(0.85, 0.75, 0.9), Color(0.98, 0.92, 0.85), light)
	Kit.block(g, Vector3(0.12, 0.04, 0.17), Vector3(0.13, 0.63, 0.08), Color(0.12, 0.1, 0.1))
	return g


## A dressing table: drawers either side, a round mirror, her scent bottles,
## her jewel box, a hat box.
static func vanity(p: Node3D, b: int, u: float, v: float, yaw := 0.0, look := MAHOGANY) -> Node3D:
	var w := 1.2
	var d := 0.48
	var g: Node3D = p.prop(b, u, v, yaw, w, d + 0.4)
	var back := -(d + 0.4) * 0.5
	var z := back + d * 0.5
	for side: float in [-1.0, 1.0]:
		Kit.block(g, Vector3(0.36, 0.72, d), Vector3(side * (w * 0.5 - 0.18), 0, z), look)
		for k in 3:
			Kit.box(g, Vector3(0.3, 0.18, 0.02), Vector3(side * (w * 0.5 - 0.18), 0.13 + k * 0.22, z + d * 0.5 + 0.01), look.lightened(0.1))
			Kit.ball(g, 0.018, Vector3(side * (w * 0.5 - 0.18), 0.13 + k * 0.22, z + d * 0.5 + 0.03), BRASS, 5)
	Kit.box(g, Vector3(w, 0.05, d), Vector3(0, 0.745, z), look.darkened(0.1))
	Kit.box(g, Vector3(w - 0.74, 0.12, 0.02), Vector3(0, 0.66, z + d * 0.5 + 0.01), look.lightened(0.1))
	runner(g, Vector3(0, 0.77, z), w - 0.2, d - 0.16, 0.06)
	var frame := Kit.cyl(g, 0.4, 0.04, Vector3(0, 1.32, back + 0.06), look, Vector3(90, 0, 0), 18)
	frame.scale = Vector3(1, 1, 1.15)
	var glass := Kit.cyl(g, 0.34, 0.03, Vector3(0, 1.32, back + 0.075), Color(0.72, 0.82, 0.88), Vector3(90, 0, 0), 18)
	glass.scale = Vector3(1, 1, 1.15)
	Kit.box(g, Vector3(0.1, 0.03, 0.006), Vector3(-0.12, 1.5, back + 0.095), Color(1, 1, 1, 0.6), Vector3(0, 0, 35))
	for k in 3:
		Kit.cyl(g, 0.035, 0.1 + 0.03 * k, Vector3(-0.42 + k * 0.08, 0.77 + 0.05 + 0.015 * k, z + 0.05), [Color(0.85, 0.6, 0.8, 0.7), Color(0.6, 0.8, 0.9, 0.7), Color(0.95, 0.8, 0.4, 0.7)][k], Vector3.ZERO, 8)
	Kit.block(g, Vector3(0.22, 0.1, 0.15), Vector3(0.36, 0.77, z + 0.02), Color(0.55, 0.2, 0.35))     # the jewel box
	Kit.box(g, Vector3(0.23, 0.012, 0.16), Vector3(0.36, 0.875, z + 0.02), BRASS)
	# the stool in front
	Kit.cyl(g, 0.2, 0.1, Vector3(0, 0.45, z + d * 0.5 + 0.18), Color(0.85, 0.55, 0.7), Vector3.ZERO, 12)
	for k in 4:
		var a := TAU * k / 4.0 + 0.78
		Kit.cyl(g, 0.018, 0.4, Vector3(cos(a) * 0.13, 0.2, z + d * 0.5 + 0.18 + sin(a) * 0.13), look, Vector3.ZERO, 5)
	return g


## A cedar chest at the foot of the bed, a folded blanket on it.
static func cedar_chest(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.1) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.48)
	var cedar := Color(0.62, 0.32, 0.2)
	Kit.block(g, Vector3(w, 0.06, 0.46), Vector3(0, 0, 0), cedar.darkened(0.3))
	Kit.block(g, Vector3(w - 0.04, 0.42, 0.44), Vector3(0, 0.06, 0), cedar)
	Kit.box(g, Vector3(w, 0.05, 0.48), Vector3(0, 0.505, 0), cedar.darkened(0.1))
	Kit.box(g, Vector3(0.12, 0.08, 0.02), Vector3(0, 0.42, 0.23), BRASS)
	Kit.block(g, Vector3(0.6, 0.1, 0.38), Vector3(-0.15, 0.53, 0), Color(0.55, 0.7, 0.85))
	Kit.box(g, Vector3(0.6, 0.02, 0.385), Vector3(-0.15, 0.6, 0), Color(0.95, 0.94, 0.9))
	return g


## Hat boxes stacked in a corner, round and striped.
static func hat_boxes(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.5, 0.5)
	var looks := [[Color(0.95, 0.85, 0.88), Color(0.6, 0.3, 0.55)], [Color(0.85, 0.9, 0.95), Color(0.2, 0.35, 0.6)], [Color(0.98, 0.94, 0.8), Color(0.75, 0.2, 0.2)]]
	var y := 0.0
	for k in 3:
		var r := 0.22 - k * 0.035
		var h := 0.22 - k * 0.02
		var lk: Array = looks[k]
		Kit.cyl(g, r, h, Vector3(0.02 * k, y + h * 0.5, -0.02 * k), lk[0], Vector3(0, 20.0 * k, 0), 14)
		Kit.cyl(g, r + 0.008, 0.04, Vector3(0.02 * k, y + h - 0.02, -0.02 * k), lk[1], Vector3(0, 20.0 * k, 0), 14)
		y += h + 0.02
	return g


# --------------------------------------------------------------- sewing room

## A treadle sewing machine in its cabinet, a chair at it, thread and scissors out.
static func sewing_machine(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.0, 1.0)
	var back := -0.5
	var wood := WALNUT
	var iron := Color(0.12, 0.12, 0.13)
	var z := back + 0.25
	for side: float in [-1.0, 1.0]:      # the iron legs, lyre-shaped
		var x := side * 0.38
		Kit.box(g, Vector3(0.04, 0.72, 0.04), Vector3(x, 0.36, z - 0.16), iron)
		Kit.box(g, Vector3(0.04, 0.72, 0.04), Vector3(x, 0.36, z + 0.16), iron)
		Kit.box(g, Vector3(0.04, 0.04, 0.42), Vector3(x, 0.03, z), iron)
		Kit.ring(g, 0.12, 0.025, Vector3(x, 0.38, z), iron, Vector3(0, 90, 0))
	Kit.box(g, Vector3(0.6, 0.03, 0.26), Vector3(0, 0.1, z + 0.02), iron, Vector3(10, 0, 0))     # the treadle
	Kit.cyl(g, 0.2, 0.03, Vector3(0.33, 0.42, z), iron, Vector3(0, 0, 90), 14)            # the wheel
	Kit.box(g, Vector3(0.94, 0.04, 0.48), Vector3(0, 0.74, z), wood)
	Kit.block(g, Vector3(0.22, 0.18, 0.44), Vector3(-0.34, 0.54, z), wood)               # drawers
	Kit.box(g, Vector3(0.16, 0.05, 0.02), Vector3(-0.34, 0.66, z + 0.225), wood.lightened(0.15))
	Kit.box(g, Vector3(0.16, 0.05, 0.02), Vector3(-0.34, 0.6, z + 0.225), wood.lightened(0.15))
	# the machine head
	var top := 0.76
	var black := Color(0.08, 0.08, 0.1)
	var gold := Color(0.88, 0.72, 0.3)
	Kit.block(g, Vector3(0.44, 0.05, 0.2), Vector3(0, top, z), black)
	Kit.block(g, Vector3(0.1, 0.26, 0.12), Vector3(0.14, top + 0.05, z), black)        # the pillar
	Kit.box(g, Vector3(0.4, 0.09, 0.11), Vector3(-0.02, top + 0.3, z), black)          # the arm
	Kit.block(g, Vector3(0.08, 0.12, 0.1), Vector3(-0.18, top + 0.15, z), black)       # the needle head
	Kit.cyl(g, 0.006, 0.08, Vector3(-0.18, top + 0.11, z + 0.02), Props.STEEL, Vector3.ZERO, 4)
	Kit.box(g, Vector3(0.3, 0.02, 0.005), Vector3(0.0, top + 0.31, z + 0.057), gold)
	Kit.box(g, Vector3(0.12, 0.012, 0.005), Vector3(0.0, top + 0.28, z + 0.057), gold)
	Kit.cyl(g, 0.07, 0.03, Vector3(0.21, top + 0.27, z), Props.STEEL, Vector3(0, 0, 90), 12)   # hand wheel
	Kit.cyl(g, 0.02, 0.05, Vector3(0.0, top + 0.37, z), Color(0.85, 0.2, 0.25), Vector3.ZERO, 6)   # a spool
	Kit.box(g, Vector3(0.14, 0.01, 0.04), Vector3(0.3, top + 0.005, z + 0.12), Props.STEEL, Vector3(0, 30, 0))   # scissors
	for k in 3:
		Kit.cyl(g, 0.018, 0.04, Vector3(-0.38 + k * 0.05, top + 0.02, z + 0.15), BLOOMS[k + 2], Vector3.ZERO, 6)
	Kit.cyl(g, 0.04, 0.03, Vector3(0.38, top + 0.015, z - 0.14), Color(0.85, 0.2, 0.25), Vector3.ZERO, 8)   # the pin cushion
	# her chair
	var cz := back + 0.78
	for x: float in [-0.17, 0.17]:
		for zz: float in [-0.16, 0.16]:
			Kit.block(g, Vector3(0.04, 0.44, 0.04), Vector3(x, 0, cz + zz), wood)
	Kit.box(g, Vector3(0.42, 0.05, 0.4), Vector3(0, 0.465, cz), wood)
	Kit.box(g, Vector3(0.4, 0.06, 0.38), Vector3(0, 0.51, cz), Color(0.85, 0.55, 0.3))
	Kit.box(g, Vector3(0.4, 0.4, 0.04), Vector3(0, 0.75, cz + 0.18), wood)
	return g


## A dressmaker's dummy on its stand, a dress pinned on it.
static func dress_form(p: Node3D, b: int, u: float, v: float, yaw := 0.0, cloth := Color(0.3, 0.55, 0.75)) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.5, 0.5)
	for k in 3:
		var a := TAU * k / 3.0
		Kit.box(g, Vector3(0.03, 0.03, 0.28), Vector3(sin(a) * 0.12, 0.03, cos(a) * 0.12), Props.WOOD_DARK, Vector3(0, rad_to_deg(a), 0))
	Kit.cyl(g, 0.02, 0.62, Vector3(0, 0.33, 0), Props.WOOD_DARK, Vector3.ZERO, 6)
	Kit.cyl(g, 0.3, 0.55, Vector3(0, 0.88, 0), cloth, Vector3.ZERO, 14, 0.13)          # the skirt
	Kit.cyl(g, 0.13, 0.2, Vector3(0, 1.25, 0), cloth.lightened(0.08), Vector3.ZERO, 12, 0.16)   # the bodice
	Kit.cyl(g, 0.165, 0.16, Vector3(0, 1.43, 0), Color(0.9, 0.86, 0.78), Vector3.ZERO, 12, 0.11)
	Kit.cyl(g, 0.03, 0.1, Vector3(0, 1.55, 0), Props.WOOD_DARK, Vector3.ZERO, 6)
	Kit.ball(g, 0.035, Vector3(0, 1.61, 0), Props.WOOD_DARK, 6)
	Kit.box(g, Vector3(0.6, 0.02, 0.02), Vector3(0, 1.34, 0.12), Color(0.98, 0.96, 0.9), Vector3(0, 0, 12))   # a tape measure
	for k in 5:
		Kit.ball(g, 0.012, Vector3(-0.08 + k * 0.04, 1.18, 0.15), Color(0.9, 0.2, 0.2), 4)
	return g


## A shelf of fabric on the bolt, folded remnants and a basket of yarn.
static func fabric_shelf(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.38)
	var wood := Color(0.92, 0.9, 0.84)
	for x: float in [-w * 0.5 + 0.02, w * 0.5 - 0.02]:
		Kit.block(g, Vector3(0.04, 1.6, 0.36), Vector3(x, 0, 0), wood)
	var bolts := [Color(0.85, 0.25, 0.35), Color(0.98, 0.85, 0.3), Color(0.3, 0.5, 0.8), Color(0.4, 0.7, 0.45), Color(0.95, 0.6, 0.75), Color(0.6, 0.35, 0.7), Color(0.95, 0.95, 0.9), Color(0.9, 0.5, 0.2)]
	for i in 4:
		var y := 0.06 + i * 0.5
		Kit.box(g, Vector3(w - 0.06, 0.03, 0.34), Vector3(0, y, 0), wood.darkened(0.05))
		if i == 3:
			continue
		# bolts of cloth lying on the shelf, ends out, a second row on the first
		var count := int((w - 0.12) / 0.15)
		var x0 := -(count - 1) * 0.075
		for k in count:
			Kit.cyl(g, 0.07, 0.3, Vector3(x0 + k * 0.15, y + 0.085, 0.0), bolts[(k * 3 + i * 5) % bolts.size()], Vector3(90, 0, 0), 12)
			Kit.cyl(g, 0.025, 0.31, Vector3(x0 + k * 0.15, y + 0.085, 0.0), Color(0.75, 0.6, 0.4), Vector3(90, 0, 0), 6)
		for k in count - 1:
			Kit.cyl(g, 0.07, 0.3, Vector3(x0 + 0.075 + k * 0.15, y + 0.215, 0.02), bolts[(k * 5 + i * 3 + 2) % bolts.size()], Vector3(90, 0, 0), 12)
			Kit.cyl(g, 0.025, 0.31, Vector3(x0 + 0.075 + k * 0.15, y + 0.215, 0.02), Color(0.75, 0.6, 0.4), Vector3(90, 0, 0), 6)
	Kit.cyl(g, 0.16, 0.16, Vector3(0, 1.66, 0), Color(0.75, 0.6, 0.38), Vector3.ZERO, 10, 0.18)     # a basket of yarn on top
	for k in 3:
		Kit.ball(g, 0.07, Vector3(-0.07 + k * 0.07, 1.8, 0.02 * k), BLOOMS[(k * 2) % BLOOMS.size()], 7)
	return g


## A day bed along a wall, a crocheted afghan of granny squares over it.
static func day_bed(p: Node3D, b: int, u: float, v: float, yaw := 0.0, l := 1.9) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, l, 0.86)
	var iron := Color(0.92, 0.9, 0.84)
	for side: float in [-1.0, 1.0]:
		Kit.block(g, Vector3(0.05, 0.9, 0.82), Vector3(side * (l * 0.5 - 0.025), 0, 0), iron)
		Kit.cyl(g, 0.03, 0.82, Vector3(side * (l * 0.5 - 0.025), 0.92, 0), iron, Vector3(90, 0, 0), 6)
	Kit.box(g, Vector3(l - 0.1, 0.5, 0.05), Vector3(0, 0.65, -0.39), iron)
	Kit.block(g, Vector3(l - 0.1, 0.42, 0.78), Vector3(0, 0.0, 0.02), Color(0.92, 0.9, 0.85))
	var granny := [Color(0.85, 0.25, 0.3), Color(0.98, 0.78, 0.25), Color(0.3, 0.6, 0.45), Color(0.55, 0.35, 0.7), Color(0.3, 0.5, 0.85), Color(0.98, 0.55, 0.2)]
	var n := int((l - 0.14) / 0.22)
	var s := (l - 0.14) / n
	for i in n:
		for k in 4:
			var at := Vector3(-l * 0.5 + 0.07 + (i + 0.5) * s, 0.43, -0.3 + k * 0.2)
			Kit.box(g, Vector3(s - 0.01, 0.025, 0.19), at, Color(0.1, 0.1, 0.1))
			Kit.box(g, Vector3(s - 0.06, 0.03, 0.14), at, granny[(i + k * 2) % granny.size()])
			Kit.box(g, Vector3(s * 0.35, 0.034, 0.06), at, granny[(i * 2 + k + 3) % granny.size()])
		Kit.box(g, Vector3(s - 0.01, 0.2, 0.02), Vector3(-l * 0.5 + 0.07 + (i + 0.5) * s, 0.32, 0.41), granny[(i + 1) % granny.size()])
	Kit.box(g, Vector3(0.3, 0.12, 0.45), Vector3(-l * 0.5 + 0.3, 0.5, -0.1), Color(0.97, 0.95, 0.9), Vector3(0, 0, 18))
	# cushions propped along the back, so it sits like a sofa by day
	var pads := [Color(0.85, 0.3, 0.4), Color(0.98, 0.8, 0.3), Color(0.35, 0.6, 0.8)]
	for k in 3:
		Kit.box(g, Vector3(0.4, 0.36, 0.1), Vector3(-0.25 + k * 0.42, 0.62, -0.27), pads[k], Vector3(-14, 0, 3.0 * (k - 1)))
		Kit.ball(g, 0.03, Vector3(-0.25 + k * 0.42, 0.62, -0.215), pads[k].darkened(0.3), 6)
	return g


# ---------------------------------------------------------------- bathroom

## A claw-foot tub, the length along its floor space's depth.
static func clawfoot(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.78, 1.7)
	var white := Color(0.96, 0.95, 0.92)
	for x: float in [-0.26, 0.26]:
		for z: float in [-0.62, 0.62]:
			Kit.ball(g, 0.06, Vector3(x, 0.07, z), BRASS, 6)
	Kit.block(g, Vector3(0.66, 0.42, 1.0), Vector3(0, 0.1, 0), white)
	for z: float in [-0.5, 0.5]:
		Kit.cyl(g, 0.33, 0.42, Vector3(0, 0.31, z), white, Vector3.ZERO, 14)
	Kit.box(g, Vector3(0.72, 0.06, 1.62), Vector3(0, 0.55, 0), white.darkened(0.04))
	Kit.box(g, Vector3(0.54, 0.02, 1.4), Vector3(0, 0.585, 0), Color(0.62, 0.78, 0.86))
	Kit.cyl(g, 0.025, 0.25, Vector3(0, 0.7, -0.74), Props.STEEL, Vector3.ZERO, 6)
	Kit.box(g, Vector3(0.025, 0.025, 0.16), Vector3(0, 0.82, -0.68), Props.STEEL)
	# a towel over the side nearer the street (local -x, with the tub turned 90)
	var pink := Color(0.98, 0.7, 0.8)
	Kit.box(g, Vector3(0.012, 0.32, 0.3), Vector3(-0.372, 0.43, 0.3), pink)
	Kit.box(g, Vector3(0.11, 0.012, 0.3), Vector3(-0.325, 0.587, 0.3), pink)
	Kit.box(g, Vector3(0.014, 0.03, 0.3), Vector3(-0.373, 0.33, 0.3), Color(0.6, 0.3, 0.5))
	return g


## A wicker laundry hamper with its lid.
static func hamper(p: Node3D, b: int, u: float, v: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.42, 0.42)
	var cane := Color(0.85, 0.75, 0.55)
	Kit.cyl(g, 0.19, 0.6, Vector3(0, 0.3, 0), cane, Vector3.ZERO, 12, 0.2)
	for k in 4:
		Kit.cyl(g, 0.198 + k * 0.001, 0.025, Vector3(0, 0.1 + k * 0.14, 0), cane.darkened(0.15), Vector3.ZERO, 12)
	Kit.cyl(g, 0.215, 0.04, Vector3(0, 0.62, 0), cane.lightened(0.05), Vector3.ZERO, 12)
	Kit.ball(g, 0.03, Vector3(0, 0.65, 0), cane.darkened(0.25), 6)
	return g


## A crocheted doll in a ball gown over the spare toilet roll, to stand on the
## toilet's tank.
static func roll_doll(parent: Node3D, pos: Vector3, look := Color(0.95, 0.75, 0.3)) -> void:
	Kit.cyl(parent, 0.085, 0.13, pos + Vector3(0, 0.065, 0), look, Vector3.ZERO, 12, 0.05)
	for k in 3:
		Kit.cyl(parent, 0.087 - k * 0.012, 0.012, pos + Vector3(0, 0.02 + k * 0.04, 0), look.lightened(0.4), Vector3.ZERO, 12)
	Kit.cyl(parent, 0.035, 0.05, pos + Vector3(0, 0.155, 0), look, Vector3.ZERO, 8)
	Kit.ball(parent, 0.035, pos + Vector3(0, 0.205, 0), _pick(SKIN, 2.0), 8)
	Kit.cyl(parent, 0.06, 0.012, pos + Vector3(0, 0.235, 0), look.lightened(0.2), Vector3.ZERO, 10)     # her hat
	Kit.cyl(parent, 0.03, 0.03, pos + Vector3(0, 0.255, 0), look, Vector3.ZERO, 8)


## A fluffy cover on a toilet lid (to go with Props.toilet), and the mat round its foot.
static func toilet_cover(parent: Node3D, look := Color(0.9, 0.6, 0.78)) -> void:
	Kit.cyl(parent, 0.2, 0.05, Vector3(0, 0.455, 0.08), look, Vector3.ZERO, 12)
	Kit.box(parent, Vector3(0.36, 0.14, 0.18), Vector3(0, 0.82, -0.22), look)
	var mat := Kit.cyl(parent, 0.34, 0.012, Vector3(0, 0.006, 0.12), look.lightened(0.1), Vector3.ZERO, 16)
	mat.scale = Vector3(1, 1, 0.8)


## A towel rail on a wall with two towels on it.
static func towels(p: Node3D, b: int, u: float, v: float, yaw := 0.0, look := Color(0.98, 0.72, 0.82)) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.7, 0.1, false)
	Kit.cyl(g, 0.012, 0.7, Vector3(0, 1.2, 0.08), Props.STEEL, Vector3(0, 0, 90), 6)
	for x: float in [-0.17, 0.17]:
		Kit.box(g, Vector3(0.3, 0.55, 0.03), Vector3(x, 0.94, 0.08), look if x < 0 else Color(0.96, 0.95, 0.92))
		Kit.box(g, Vector3(0.3, 0.04, 0.032), Vector3(x, 0.74, 0.08), Color(0.6, 0.3, 0.5))
	return g


# ----------------------------------------------------------------- the porch

## A porch glider: a metal settee that swings on its frame, a scalloped shell
## back, a cushion.
static func glider(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.7, paint := Color(0.5, 0.76, 0.68)) -> Node3D:
	var d := 0.74
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	var rail := paint.darkened(0.35)
	for side: float in [-1.0, 1.0]:
		var x := side * (w * 0.5 - 0.04)
		Kit.box(g, Vector3(0.04, 0.04, d - 0.04), Vector3(x, 0.02, 0), rail)
		for z: float in [-d * 0.5 + 0.1, d * 0.5 - 0.1]:
			Kit.box(g, Vector3(0.035, 0.42, 0.035), Vector3(x, 0.23, z), rail)
		Kit.box(g, Vector3(0.04, 0.04, d - 0.18), Vector3(x, 0.44, 0), rail)
		Kit.box(g, Vector3(0.1, 0.36, d - 0.22), Vector3(side * (w * 0.5 - 0.12), 0.62, 0.02), paint)      # the arms
		Kit.box(g, Vector3(0.13, 0.04, d - 0.18), Vector3(side * (w * 0.5 - 0.12), 0.81, 0.04), paint.lightened(0.1))
	Kit.box(g, Vector3(w - 0.3, 0.06, d - 0.22), Vector3(0, 0.46, 0.05), paint)
	Kit.box(g, Vector3(w - 0.32, 0.16, 0.04), Vector3(0, 0.38, d * 0.5 - 0.075), paint.darkened(0.1))
	Kit.box(g, Vector3(w - 0.34, 0.08, d - 0.3), Vector3(0, 0.53, 0.07), Color(0.9, 0.85, 0.55))         # the cushion
	var bz := -d * 0.5 + 0.12
	Kit.box(g, Vector3(w - 0.3, 0.42, 0.05), Vector3(0, 0.72, bz), paint)
	var n := 5
	var sw := (w - 0.3) / n
	for i in n:
		var x := -(w - 0.3) * 0.5 + (i + 0.5) * sw
		Kit.cyl(g, sw * 0.5, 0.05, Vector3(x, 0.93, bz), paint, Vector3(90, 0, 0), 12)
		for k in 3:
			Kit.box(g, Vector3(0.02, 0.32, 0.054), Vector3(x - sw * 0.25 + k * sw * 0.25, 0.75, bz), paint.darkened(0.12))
	return g


## A wooden rocking chair with a gingham cushion.
static func rocker(p: Node3D, b: int, u: float, v: float, yaw := 0.0, look := WHITE, pad := Color(0.85, 0.3, 0.3)) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.62, 0.86)
	for side: float in [-1.0, 1.0]:
		var x := side * 0.25
		Kit.box(g, Vector3(0.045, 0.045, 0.56), Vector3(x, 0.03, 0.0), look)                      # the rocker
		Kit.box(g, Vector3(0.045, 0.045, 0.18), Vector3(x, 0.055, 0.35), look, Vector3(-22, 0, 0))
		Kit.box(g, Vector3(0.045, 0.045, 0.18), Vector3(x, 0.055, -0.35), look, Vector3(22, 0, 0))
		Kit.box(g, Vector3(0.04, 0.45, 0.04), Vector3(x, 0.27, 0.17), look)                        # legs
		Kit.box(g, Vector3(0.04, 1.1, 0.04), Vector3(x, 0.6, -0.2), look, Vector3(-8, 0, 0))
		Kit.box(g, Vector3(0.06, 0.035, 0.46), Vector3(x + side * 0.02, 0.68, 0.0), look)           # arms
		Kit.box(g, Vector3(0.035, 0.2, 0.035), Vector3(x, 0.57, 0.17), look)
	Kit.box(g, Vector3(0.54, 0.05, 0.46), Vector3(0, 0.47, -0.01), look)
	var check := Kit.tex("lino", 0.2, pad, false, Color(1.0, 0.5, 0.48))
	Kit.box(g, Vector3(0.46, 0.05, 0.4), Vector3(0, 0.52, 0.0), check)
	for k in 5:
		Kit.box(g, Vector3(0.03, 0.55, 0.025), Vector3(-0.18 + k * 0.09, 0.82, -0.25), look, Vector3(-8, 0, 0))
	Kit.box(g, Vector3(0.56, 0.08, 0.04), Vector3(0, 1.12, -0.29), look, Vector3(-8, 0, 0))
	return g


## A square porch post on a plinth, with a capital and scrolled brackets
## either side at the top. `h` is the height of the porch ceiling.
static func porch_post(p: Node3D, b: int, u: float, v: float, h := 2.62, look := WHITE, brackets := true) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.2, 0.2)
	Kit.block(g, Vector3(0.2, 0.32, 0.2), Vector3.ZERO, look.darkened(0.06))
	Kit.block(g, Vector3(0.13, h - 0.52, 0.13), Vector3(0, 0.32, 0), look)
	Kit.block(g, Vector3(0.19, 0.08, 0.19), Vector3(0, h - 0.2, 0), look.darkened(0.06))
	Kit.block(g, Vector3(0.15, 0.12, 0.15), Vector3(0, h - 0.12, 0), look)
	if brackets:
		for side: float in [-1.0, 1.0]:
			Kit.box(g, Vector3(0.34, 0.05, 0.05), Vector3(side * 0.16, h - 0.2, 0), look, Vector3(0, 0, side * 40.0))
			Kit.ball(g, 0.035, Vector3(side * 0.08, h - 0.32, 0), look, 6)
	return g


## A porch railing along u (or along v) at `at`: a top rail, a bottom rail and
## square balusters. It takes up its line of floor.
static func porch_rail(p: Node3D, b: int, along_u: bool, at: float, from: float, to: float, h := 0.86, look := WHITE) -> void:
	var n: Node3D = p.node_of(b)
	p.slab(n, along_u, at, from, to, h - 0.06, h, 0.1, look)
	p.slab(n, along_u, at, from, to, 0.09, 0.15, 0.07, look.darkened(0.05))
	var count := maxi(int((to - from) / 0.13), 1)
	for i in range(1, count):
		var w := from + (to - from) * float(i) / float(count)
		Kit.box(n, Vector3(0.045, h - 0.21, 0.045), p.pt(w, at, 0.15 + (h - 0.21) * 0.5) if along_u else p.pt(at, w, 0.15 + (h - 0.21) * 0.5), look)
	if along_u:
		p.block(from, at - 0.05, to, at + 0.05)
	else:
		p.block(at - 0.05, from, at + 0.05, to)


## A fern in a basket hanging on three chains from `hook` (on the ceiling).
static func hanging_fern(parent: Node3D, hook: Vector3, drop := 0.6) -> void:
	var at := hook - Vector3(0, drop, 0)
	for k in 3:
		var a := TAU * k / 3.0
		var foot := at + Vector3(cos(a) * 0.15, 0.1, sin(a) * 0.15)
		var c := Kit.cyl(parent, 0.006, (hook - foot).length(), (hook + foot) * 0.5, Props.STEEL, Vector3.ZERO, 4)
		c.basis = Basis(Quaternion(Vector3.UP, (hook - foot).normalized()))
	Kit.cyl(parent, 0.17, 0.16, at, Color(0.72, 0.42, 0.26), Vector3.ZERO, 10, 0.2)
	Kit.ball(parent, 0.17, at + Vector3(0, 0.08, 0), LEAF.darkened(0.15), 8)
	for i in 12:
		var arm := Kit.group(parent, at + Vector3(0, 0.08, 0), Vector3(0, 30.0 * i, 0))
		var tip := Kit.group(arm, Vector3.ZERO, Vector3(-55.0 - 25.0 * Props.rnd(i * 2.3), 0, 0))
		Kit.box(tip, Vector3(0.09, 0.02, 0.4), Vector3(0, 0, 0.19), LEAF.lightened(0.12 * (i % 2)))


## A porch lantern on a wall, lit.
static func lantern(parent: Node3D, pos: Vector3, yaw := 0.0) -> void:
	var g := Kit.group(parent, pos, Vector3(0, yaw, 0))
	Kit.box(g, Vector3(0.12, 0.2, 0.03), Vector3(0, 0, 0.015), Props.DARK)
	Kit.box(g, Vector3(0.03, 0.03, 0.12), Vector3(0, 0.0, 0.08), Props.DARK)
	Kit.box(g, Vector3(0.16, 0.24, 0.16), Vector3(0, -0.04, 0.2), Kit.flat(Color(1.0, 0.85, 0.5), 1.4))
	Kit.box(g, Vector3(0.2, 0.04, 0.2), Vector3(0, 0.1, 0.2), Props.DARK)
	Kit.cyl(g, 0.03, 0.06, Vector3(0, 0.14, 0.2), Props.DARK, Vector3.ZERO, 6)
	Kit.omni(g, Vector3(0, -0.05, 0.45), Color(1.0, 0.8, 0.5), 0.9, 4.0)


## A mailbox on a wall, the paper stuck in it.
static func mailbox(parent: Node3D, pos: Vector3, yaw := 0.0) -> void:
	var g := Kit.group(parent, pos, Vector3(0, yaw, 0))
	Kit.box(g, Vector3(0.3, 0.36, 0.1), Vector3(0, 0, 0.05), Color(0.2, 0.22, 0.24))
	Kit.box(g, Vector3(0.32, 0.04, 0.14), Vector3(0, 0.19, 0.07), Color(0.25, 0.27, 0.3))
	Kit.box(g, Vector3(0.22, 0.06, 0.02), Vector3(0.0, 0.2, 0.12), Props.PAPER, Vector3(0, 0, 8))


# ------------------------------------------------------------------- the yard

## A white picket fence along u (or along v) at `at`: pointed pickets on two
## rails behind, posts with caps. `gaps` [[from, to], ...] are left open as
## gateways between the rooms either side (place.gd's fence makes the way
## through). It takes up its line of floor.
static func pickets(p: Node3D, b: int, along_u: bool, at: float, from: float, to: float, gaps := [], h := 0.95, look := WHITE, back := -1.0) -> void:
	var n: Node3D = p.node_of(b)
	var cuts := gaps.duplicate()
	cuts.sort_custom(func(a: Array, c: Array) -> bool: return a[0] < c[0])
	var runs: Array = []
	var cursor := from
	for gap: Array in cuts:
		runs.append([cursor, gap[0]])
		cursor = gap[1]
		p.fence(b, along_u, at, gap[0], gap[1], [[gap[0], gap[1]]])
	runs.append([cursor, to])
	for run: Array in runs:
		var length: float = run[1] - run[0]
		if length < 0.05:
			continue
		for y: float in [h * 0.22, h * 0.72]:
			p.slab(n, along_u, at + back * 0.035, run[0], run[1], y, y + 0.06, 0.035, look.darkened(0.1))
		var count := maxi(int(round(length / 0.13)), 1)
		for i in count:
			var w: float = run[0] + (i + 0.5) * length / count
			var where: Vector3 = p.pt(w, at, (h - 0.06) * 0.5) if along_u else p.pt(at, w, (h - 0.06) * 0.5)
			Kit.box(n, Vector3(0.075, h - 0.06, 0.022) if along_u else Vector3(0.022, h - 0.06, 0.075), where, look)
			Kit.box(n, Vector3(0.053, 0.053, 0.022) if along_u else Vector3(0.022, 0.053, 0.053), where + Vector3(0, (h - 0.06) * 0.5, 0), look, Vector3(0, 0, 45) if along_u else Vector3(45, 0, 0))
		var posts := maxi(int(round(length / 2.0)), 1)
		for i in posts + 1:
			var w: float = run[0] + length * float(i) / float(posts)
			var foot: Vector3 = p.pt(w, at + back * 0.06, 0.0) if along_u else p.pt(at + back * 0.06, w, 0.0)
			Kit.block(n, Vector3(0.09, h + 0.04, 0.09), foot, look.darkened(0.04))
			Kit.block(n, Vector3(0.12, 0.04, 0.12), foot + Vector3(0, h + 0.04, 0), look)
		if along_u:
			p.block(run[0], at - 0.1, run[1], at + 0.04)
		else:
			p.block(at - 0.1, run[0], at + 0.04, run[1])


## A low wire fence with a row of hoops along its top (a neighbour's yard).
## Decoration only: put it where nobody walks.
static func hoop_fence(p: Node3D, n: Node3D, along_u: bool, at: float, from: float, to: float, h := 0.75, look := Color(0.25, 0.27, 0.28)) -> void:
	var length := to - from
	for i in int(length / 1.8) + 1:
		var w := from + minf(i * 1.8, length)
		Kit.cyl(n, 0.025, h + 0.08, p.pt(w, at, (h + 0.08) * 0.5) if along_u else p.pt(at, w, (h + 0.08) * 0.5), look, Vector3.ZERO, 6)
	p.slab(n, along_u, at, from, to, h - 0.02, h, 0.02, look)
	p.slab(n, along_u, at, from, to, 0.1, 0.12, 0.02, look)
	var k := 0
	var w0 := from + 0.12
	while w0 < to - 0.12:
		Kit.ring(n, 0.13, 0.008, p.pt(w0, at, h - 0.13) if along_u else p.pt(at, w0, h - 0.13), look, Vector3.ZERO if along_u else Vector3(0, 90, 0))
		for x: float in [-0.06, 0.06]:
			Kit.cyl(n, 0.005, h - 0.25, p.pt(w0 + x, at, 0.11 + (h - 0.25) * 0.5) if along_u else p.pt(at, w0 + x, 0.11 + (h - 0.25) * 0.5), look, Vector3.ZERO, 4)
		w0 += 0.13
		k += 1


## A bed of flowers: dark earth behind a brick edge, clumps of leaves with
## blooms on top. It takes up floor.
static func flower_bed(p: Node3D, b: int, u: float, v: float, w: float, d: float, key := 0.0, edge := true) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, w, d)
	Kit.box(g, Vector3(w, 0.05, d - 0.02), Vector3(0, 0.025, -0.01), SOIL)
	if edge:
		var count := maxi(int(w / 0.22), 1)
		for i in count:
			Kit.box(g, Vector3(w / count - 0.02, 0.1, 0.07), Vector3(-w * 0.5 + (i + 0.5) * w / count, 0.05, d * 0.5 - 0.035), Color(0.62, 0.3, 0.24).darkened(0.08 * (i % 2)), Vector3(0, 0, 4.0 * (Props.rnd(key + i) - 0.5)))
	var cols := maxi(int(w / 0.3), 1)
	var rows := maxi(int(d / 0.3), 1)
	for i in cols:
		for k in rows:
			var s := key + i * 1.37 + k * 5.1
			var at := Vector3(-w * 0.5 + (i + 0.5) * w / cols + 0.06 * (Props.rnd(s) - 0.5), 0.05, -d * 0.5 + (k + 0.5) * d / rows - (0.03 if edge else 0.0))
			var tall := 0.12 + 0.12 * Props.rnd(s + 1.0) + 0.1 * k
			Kit.ball(g, 0.13, at + Vector3(0, tall * 0.6, 0), LEAF.darkened(0.12 * ((i + k) % 2)), 7)
			var c := _pick(BLOOMS, s + 2.0)
			for f in 4:
				var a := TAU * f / 4.0 + Props.rnd(s + 3.0)
				Kit.ball(g, 0.045, at + Vector3(cos(a) * 0.07, tall * 0.6 + 0.1 + 0.03 * (f % 2), sin(a) * 0.07), c, 6)
	return g


## A clay pot of red geraniums, to stand on something.
static func geraniums(parent: Node3D, pos: Vector3) -> void:
	Kit.cyl(parent, 0.13, 0.22, pos + Vector3(0, 0.11, 0), Color(0.75, 0.38, 0.24), Vector3.ZERO, 10, 0.16)
	Kit.cyl(parent, 0.17, 0.04, pos + Vector3(0, 0.22, 0), Color(0.72, 0.36, 0.22), Vector3.ZERO, 10)
	Kit.ball(parent, 0.16, pos + Vector3(0, 0.32, 0), LEAF, 8)
	for k in 5:
		var a := TAU * k / 5.0
		Kit.ball(parent, 0.06, pos + Vector3(cos(a) * 0.09, 0.43 + 0.03 * (k % 2), sin(a) * 0.09), Color(0.92, 0.15, 0.2), 6)


# ---------------------------------------------------------------- neighbours

## A neighbour's frame house, seen from the street: its front on the building
## line at v from u0, w wide, `look` its walls with clapboard `line`s; a
## porch with a roof on posts across the front, its side wall running back
## (`side`: -1 on the left, +1 on the right, 0 neither), and lit windows if
## `lit`. Decoration only: built in the node n, nowhere anybody walks.
static func neighbour(p: Node3D, b: int, u0: float, v: float, w: float, look: Variant, line: Color, trim: Color, door: Color, lit := true, side := 0, porch_d := 2.3) -> void:
	var n: Node3D = p.node_of(b)
	var u1 := u0 + w
	var hi := 5.8
	p.slab(n, true, v, u0, u1, 0.0, hi, 0.15, look)
	var glow: Variant = Kit.flat(Color(1.0, 0.82, 0.52), 0.55) if lit else Color(0.18, 0.22, 0.3)
	var door_u := u0 + w * 0.68
	var wins := [[u0 + 0.9, u0 + 0.9 + w * 0.32, 0.8, 2.2, glow], [u0 + 1.0, u0 + 2.2, 3.4, 4.9, Color(0.18, 0.22, 0.3)], [u1 - 2.4, u1 - 1.2, 3.4, 4.9, glow]]
	var hole_list: Array = [[door_u - 0.55, door_u + 0.55, -1.0, 2.25]]
	for win: Array in wins:
		hole_list.append([win[0] - 0.1, win[1] + 0.1, win[2] - 0.1, win[3] + 0.1])
	siding(p, n, true, v, u0, u1, 1.0, 0.0, hi, line, hole_list)
	for win: Array in wins:
		p.slab(n, true, v + 0.1, win[0] - 0.07, win[1] + 0.07, win[2] - 0.07, win[3] + 0.07, 0.04, trim)
		p.slab(n, true, v + 0.115, win[0], win[1], win[2], win[3], 0.03, win[4])
		p.slab(n, true, v + 0.13, win[0] + 0.006, win[1] - 0.006, (win[2] + win[3]) * 0.5 - 0.02, (win[2] + win[3]) * 0.5 + 0.02, 0.02, trim)
	p.slab(n, true, v + 0.1, door_u - 0.52, door_u + 0.52, 0.0, 2.2, 0.04, trim)
	p.slab(n, true, v + 0.115, door_u - 0.45, door_u + 0.45, 0.0, 2.13, 0.03, door)
	p.slab(n, true, v, u0 - 0.1, u1 + 0.1, hi, hi + 0.25, 0.5, trim)
	# the porch: floor, posts, a roof, a solid rail with a gap at the steps
	var front := v + porch_d
	Kit.box(n, Vector3(w - 0.01, 0.05, porch_d - 0.08), p.pt(u0 + w * 0.5, v + 0.08 + (porch_d - 0.08) * 0.5, 0.025), Color(0.5, 0.52, 0.56))
	for k in 4:
		var pu := u0 + 0.15 + (w - 0.3) * k / 3.0
		Kit.block(n, Vector3(0.14, 2.57, 0.14), p.pt(pu, front - 0.12, 0.05), trim)
	Kit.box(n, Vector3(w + 0.3, 0.12, porch_d + 0.2), p.pt(u0 + w * 0.5, v + porch_d * 0.5 + 0.1, 2.68), Color(0.32, 0.3, 0.3))
	Kit.box(n, Vector3(w + 0.32, 0.26, 0.06), p.pt(u0 + w * 0.5, front + 0.18, 2.58), trim)
	for seg: Array in [[u0 + 0.2, door_u - 0.7], [door_u + 0.7, u1 - 0.2]]:
		p.slab(n, true, front - 0.12, seg[0], seg[1], 0.86, 0.92, 0.08, trim)
		p.slab(n, true, front - 0.12, seg[0], seg[1], 0.05, 0.86, 0.03, trim.darkened(0.12))
	Kit.box(n, Vector3(1.2, 0.03, 0.5), p.pt(door_u, front + 0.25, 0.015), Color(0.62, 0.6, 0.58))
	if side != 0:
		var su := u0 if side < 0 else u1
		p.slab(n, false, su, v - 8.5, v, 0.0, hi, 0.15, look)
		siding(p, n, false, su, v - 8.5, v, float(side), 0.0, hi, line, [[v - 6.0, v - 4.8, 0.9, 2.3], [v - 3.0, v - 1.8, 3.3, 4.8]])
		for win: Array in [[v - 6.0, v - 4.8, 0.9, 2.3], [v - 3.0, v - 1.8, 3.3, 4.8]]:
			p.slab(n, false, su + side * 0.1, win[0] - 0.07, win[1] + 0.07, win[2] - 0.07, win[3] + 0.07, 0.04, trim)
			p.slab(n, false, su + side * 0.115, win[0], win[1], win[2], win[3], 0.03, glow)
			p.slab(n, false, su + side * 0.13, win[0] + 0.006, win[1] - 0.006, (win[2] + win[3]) * 0.5 - 0.02, (win[2] + win[3]) * 0.5 + 0.02, 0.02, trim)
		p.slab(n, false, su + side * 0.1, v - 8.6, v + 0.1, hi, hi + 0.25, 0.4, trim)
