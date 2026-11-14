extends RefCounted
## Pieces for the clothing store (plans/clothes.gd): the hat wall, the jacket
## rail, the jeans cubbies, the sneaker wall and its try-on bench, the shirt
## table and the jersey stand, the glass counter, the window dummies, the
## fitting booths, the three-way mirror, and the stock room's rail and boxes.
##
##   const Wear := preload("res://scripts/props_clothes.gd")
##   Wear.hat_wall(p, band, u, v, yaw)
##
## The same rules as props.gd: (u, v) is the middle of the floor a piece takes
## up, `yaw` the way its front faces (0 the street, 90 right, 180 the back, 270
## left), and that floor is kept clear of walkers. A wall display stands with
## its back on the wall. The small things (a cap, a sneaker, a jacket, a dummy)
## are built into a group you give, at a point in that group's space.

const Props := preload("res://scripts/props.gd")

const CHROME := Color(0.78, 0.8, 0.84)
const DARK := Color(0.13, 0.13, 0.15)
const WHITE := Color(0.95, 0.94, 0.9)
const GOLD := Color(0.98, 0.76, 0.22)
const MIRROR := Color(0.7, 0.83, 0.9)
const CLEAR := Color(0.78, 0.9, 0.95, 0.3)        # acrylic shelves, a glass counter top

## Loud 1990s colours: puffer jackets, caps, T-shirts, jerseys.
const LOUD := [Color(0.86, 0.14, 0.12), Color(0.14, 0.3, 0.82), Color(0.98, 0.76, 0.1), Color(0.1, 0.52, 0.3),
		Color(0.13, 0.13, 0.15), Color(0.5, 0.2, 0.66), Color(0.96, 0.46, 0.08), Color(0.06, 0.58, 0.6), Color(0.93, 0.93, 0.9)]
## Denim washes, and khaki: indigo, mid blue, stonewash, black, khaki.
const DENIM := [Color(0.15, 0.2, 0.42), Color(0.26, 0.38, 0.62), Color(0.52, 0.64, 0.82), Color(0.14, 0.14, 0.17), Color(0.76, 0.64, 0.42)]
## Sneakers: the upper, then the trim (the stripe, the collar, the heel).
const KICKS := [[WHITE, Color(0.86, 0.14, 0.12)], [WHITE, Color(0.14, 0.3, 0.82)], [DARK, Color(0.86, 0.14, 0.12)], [WHITE, DARK],
		[Color(0.86, 0.14, 0.12), WHITE], [Color(0.14, 0.3, 0.82), WHITE], [WHITE, Color(0.1, 0.52, 0.3)], [DARK, Color(0.98, 0.76, 0.1)],
		[WHITE, Color(0.5, 0.2, 0.66)], [Color(0.55, 0.57, 0.6), Color(0.06, 0.58, 0.6)]]
## Shoe boxes: the box, then its lid.
const BOXES := [[Color(0.95, 0.5, 0.12), WHITE], [DARK, Color(0.82, 0.14, 0.12)], [WHITE, Color(0.16, 0.3, 0.75)],
		[Color(0.8, 0.14, 0.12), DARK], [Color(0.55, 0.75, 0.9), WHITE], [Color(0.62, 0.48, 0.3), DARK], [Color(0.3, 0.3, 0.33), Color(0.95, 0.5, 0.12)]]


## A steady pick from a list (Props.rnd), so the shop looks the same every run.
static func pick(list: Array, key: float) -> Variant:
	return list[int(Props.rnd(key) * list.size()) % list.size()]


## A pair of display spotlights over a wall display, one each side of its sign:
## a plate on the wall at each of `xs` (the display's back is at z = `back`,
## the plate's middle at height y), an arm out from it, and a black can on the
## end tipped down and back at the display, its lens lit.
static func spots(g: Node3D, xs: Array, y: float, back: float, reach := 0.32, tilt := 42.0) -> void:
	for x: float in xs:
		Kit.box(g, Vector3(0.07, 0.07, 0.02), Vector3(x, y, back + 0.01), DARK)
		Kit.box(g, Vector3(0.022, 0.022, reach), Vector3(x, y, back + 0.02 + reach * 0.5), DARK)
		var can := Kit.group(g, Vector3(x, y - 0.02, back + 0.02 + reach), Vector3(tilt, 0, 0))
		Kit.cyl(can, 0.05, 0.13, Vector3(0, -0.05, 0), DARK, Vector3.ZERO, 10, 0.04)
		Kit.cyl(can, 0.043, 0.008, Vector3(0, -0.113, 0), Kit.flat(Color(1.0, 0.93, 0.75), 2.2), Vector3.ZERO, 10)


# ------------------------------------------------------------------- hats

## A baseball cap facing +z, the bottom of its crown at `pos`. `lean` tips it
## back (degrees) so the front panel shows, as on a hat wall.
static func cap(parent: Node3D, pos: Vector3, crown: Color, brim: Color, lean := -10.0, patch: Variant = null) -> Node3D:
	var g := Kit.group(parent, pos, Vector3(lean, 0, 0))
	Kit.cyl(g, 0.1, 0.07, Vector3(0, 0.035, 0), crown, Vector3.ZERO, 12, 0.088)
	var dome := Kit.ball(g, 0.089, Vector3(0, 0.07, 0), crown, 12)
	dome.scale = Vector3(1, 0.62, 1)
	Kit.ball(g, 0.016, Vector3(0, 0.124, 0), brim, 6)
	Kit.box(g, Vector3(0.17, 0.016, 0.13), Vector3(0, 0.01, 0.145), brim, Vector3(7, 0, 0))
	Kit.box(g, Vector3(0.075, 0.045, 0.012), Vector3(0, 0.055, 0.094), patch if patch is Color else brim, Vector3(-14, 0, 0))
	return g


## A knitted beanie with a turned-up cuff, standing at `pos` (pom: a Color, or null).
static func beanie(parent: Node3D, pos: Vector3, knit: Color, cuff: Color, pom: Variant = null) -> Node3D:
	var g := Kit.group(parent, pos)
	Kit.cyl(g, 0.082, 0.12, Vector3(0, 0.06, 0), knit, Vector3.ZERO, 10, 0.076)
	var top := Kit.ball(g, 0.077, Vector3(0, 0.12, 0), knit, 10)
	top.scale = Vector3(1, 0.72, 1)
	Kit.cyl(g, 0.088, 0.055, Vector3(0, 0.03, 0), cuff, Vector3.ZERO, 10, 0.086)
	if pom is Color:
		Kit.ball(g, 0.036, Vector3(0, 0.18, 0), pom, 8)
	return g


## The hat wall: rows of caps on pegs on a pegboard, beanies on a ledge under
## them, a lit HATS sign on top. Its back on the wall.
static func hat_wall(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.8) -> Node3D:
	var d := 0.42
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	var back := -d * 0.5
	var board := Color(0.8, 0.66, 0.46)          # brown hardboard
	Kit.box(g, Vector3(w + 0.1, 1.86, 0.03), Vector3(0, 1.55, back + 0.015), Props.WOOD_DARK)
	Kit.box(g, Vector3(w, 1.76, 0.03), Vector3(0, 1.55, back + 0.025), board)
	var front := back + 0.04
	# The holes: a dot every 10 cm, in the strips between the rows of caps.
	var holes := board.darkened(0.45)
	for row: float in [0.74, 2.38]:
		for i in int(w / 0.1):
			Kit.box(g, Vector3(0.018, 0.018, 0.004), Vector3(-w * 0.5 + 0.05 + i * 0.1, row, front + 0.002), holes)
	# Beanies on the ledge at the bottom.
	Kit.box(g, Vector3(w - 0.04, 0.03, 0.2), Vector3(0, 0.83, front + 0.1), Props.WOOD_DARK)
	var cols := maxi(int(w / 0.3), 2)
	for c in cols + 1:
		var key := u * 1.3 + v * 0.7 + c * 1.9
		var knit: Color = pick(LOUD, key)
		beanie(g, Vector3(-w * 0.5 + (c + 0.5) * w / (cols + 1), 0.845, front + 0.1), knit, knit.lightened(0.25) if Props.rnd(key + 1.0) > 0.5 else knit.darkened(0.2), pick(LOUD, key + 2.0) if Props.rnd(key + 3.0) > 0.4 else null)
	# Caps on pegs, four rows.
	for r in 4:
		for c in cols:
			var key := u * 1.3 + v * 0.7 + r * 7.1 + c * 1.9 + 31.0
			var x := -w * 0.5 + (c + 0.5) * w / cols
			var y := 1.12 + r * 0.33
			Kit.cyl(g, 0.008, 0.1, Vector3(x, y + 0.05, front + 0.05), Props.STEEL, Vector3(90, 0, 0), 4)
			var crown: Color = pick(LOUD, key)
			var brim: Color = crown if Props.rnd(key + 4.0) > 0.45 else pick(LOUD, key + 5.0)
			var hat := cap(g, Vector3(x, y, front + 0.13), crown, brim, 16.0, WHITE if crown != WHITE else Color(0.86, 0.14, 0.12))
			hat.scale = Vector3.ONE * 1.3
	Props.sign_box(g, "HATS", Vector3(0, 2.68, back + 0.07), Vector2(1.0, 0.32), Color(0.98, 0.78, 0.12), DARK, 0.0, 0.5)
	spots(g, [-0.72, 0.72], 2.72, back)
	return g


# ---------------------------------------------------------------- jackets

## A puffer jacket hanging face-out (its front to +z), its hanger at `top`:
## fat quilted bands, sleeves down each side, a zip, a collar or a hood.
## `trim` colours the top band (colour-block) when `block` is set, and the cuffs.
static func puffer_front(parent: Node3D, top: Vector3, shell: Color, trim: Color, hood := false, block := false, thick := 0.14, w := 0.48, h := 0.62) -> void:
	var y0 := top.y - 0.04
	Kit.box(parent, Vector3(w - 0.04, h, thick - 0.04), Vector3(top.x, y0 - h * 0.5, top.z), shell.darkened(0.4))
	for k in 4:
		var look := trim if block and k == 0 else shell
		Kit.box(parent, Vector3(w, h * 0.25 - 0.016, thick), Vector3(top.x, y0 - (k + 0.5) * h * 0.25, top.z), look)
	for s: float in [-1.0, 1.0]:
		Kit.box(parent, Vector3(0.11, h - 0.06, thick - 0.02), Vector3(top.x + s * (w * 0.5 + 0.06), y0 - (h - 0.06) * 0.5 - 0.03, top.z), shell.darkened(0.1))
		Kit.box(parent, Vector3(0.115, 0.05, thick - 0.015), Vector3(top.x + s * (w * 0.5 + 0.06), y0 - h + 0.035, top.z), trim)
	Kit.box(parent, Vector3(0.018, h - 0.02, 0.006), Vector3(top.x, y0 - h * 0.5, top.z + thick * 0.5 + 0.003), Color(0.8, 0.8, 0.82))
	if hood:
		Kit.box(parent, Vector3(w * 0.62, 0.17, thick * 0.8), Vector3(top.x, y0 + 0.05, top.z - thick * 0.25), trim if block else shell.darkened(0.12))
	else:
		Kit.box(parent, Vector3(w * 0.55, 0.08, thick + 0.02), Vector3(top.x, y0 + 0.02, top.z), trim if block else shell.darkened(0.15))


## A puffer jacket (or a vest) hanging side-on from a rail at `top`: its front
## faces +x, along the rail; it sticks out along z, with the far sleeve down
## its outer end.
static func puffer_side(parent: Node3D, top: Vector3, shell: Color, trim: Color, vest := false, block := false) -> void:
	var h := 0.46 if vest else 0.6
	var n := 3 if vest else 4
	var y0 := top.y - 0.06
	Kit.box(parent, Vector3(0.012, 0.07, 0.012), Vector3(top.x, top.y + 0.015, top.z), Props.STEEL)
	Kit.box(parent, Vector3(0.1, h, 0.38), Vector3(top.x, y0 - h * 0.5, top.z), shell.darkened(0.4))
	for k in n:
		Kit.box(parent, Vector3(0.14, h / n - 0.016, 0.44), Vector3(top.x, y0 - (k + 0.5) * h / n, top.z), trim if block and k == 0 else shell)
	Kit.box(parent, Vector3(0.11, 0.07, 0.24), Vector3(top.x, y0 + 0.02, top.z), trim if block else shell.darkened(0.15))
	if not vest:
		Kit.box(parent, Vector3(0.11, h - 0.08, 0.1), Vector3(top.x, y0 - (h - 0.08) * 0.5 - 0.04, top.z + 0.25), shell.darkened(0.1))
		Kit.box(parent, Vector3(0.115, 0.05, 0.105), Vector3(top.x, y0 - h + 0.06, top.z + 0.25), trim)


## The jacket rail: a long bar of puffers and vests hung side-on, with a row of
## jackets face-out on the wall above it and the name over the top. Its back
## on the wall.
static func jacket_rail(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 3.4) -> Node3D:
	var d := 0.62
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	var back := -d * 0.5
	var slat := Color(0.24, 0.25, 0.28)
	Kit.box(g, Vector3(w, 2.2, 0.03), Vector3(0, 1.3, back + 0.015), slat)
	for i in 15:
		Kit.box(g, Vector3(w, 0.014, 0.008), Vector3(0, 0.33 + i * 0.14, back + 0.032), slat.darkened(0.35))
	# The bar, on brackets out of the wall.
	var bar_y := 1.32
	var bar_z := back + 0.33
	var brackets := maxi(int(w / 1.2), 1)
	for i in brackets + 1:
		Kit.box(g, Vector3(0.03, 0.04, 0.32), Vector3(-w * 0.5 + 0.08 + i * (w - 0.16) / brackets, bar_y, back + 0.17), Props.STEEL)
	Kit.cyl(g, 0.015, w - 0.12, Vector3(0, bar_y, bar_z), CHROME, Vector3(0, 0, 90), 6)
	var n := int((w - 0.3) / 0.19)
	for i in n:
		var key := u * 3.1 + v * 1.7 + i * 2.3
		var x := -w * 0.5 + 0.2 + i * (w - 0.4) / float(n - 1)
		puffer_side(g, Vector3(x, bar_y, bar_z), pick(LOUD, key), pick(LOUD, key + 1.1), Props.rnd(key + 2.0) > 0.72, Props.rnd(key + 3.0) > 0.6)
	# Face-out on the wall above, on hooks.
	var m := maxi(int(w / 0.82), 1)
	for i in m:
		var key := u * 2.7 + v * 1.1 + i * 4.1 + 9.0
		var x := -w * 0.5 + (i + 0.5) * w / m
		Kit.box(g, Vector3(0.025, 0.025, 0.12), Vector3(x, 2.3, back + 0.09), Props.STEEL)
		var shell: Color = pick(LOUD, key)
		var trim: Color = pick(LOUD, key + 1.3)
		if trim == shell:
			trim = DARK if shell != DARK else Color(0.86, 0.14, 0.12)
		puffer_front(g, Vector3(x, 2.3, back + 0.13), shell, trim, i % 2 == 1, i % 2 == 0)
	Props.sign_box(g, "JACKETS", Vector3(0, 2.68, back + 0.07), Vector2(1.5, 0.32), Color(0.86, 0.14, 0.12), WHITE, 0.0, 0.5)
	spots(g, [-1.0, 1.0], 2.72, back)
	return g


# ----------------------------------------------------------------- jeans

## Cubbyhole shelving of folded jeans: a column of each wash (indigo, mid blue,
## stonewash, black, khaki), a stack in every hole. Its back on the wall.
static func jeans_wall(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 2.0) -> Node3D:
	var d := 0.42
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	var wood := Color(0.88, 0.8, 0.62)
	var h := 2.24
	var y0 := 0.14
	var cols := maxi(int(w / 0.4), 1)
	var rows := 5
	var cw := (w - 0.04) / cols
	var ch := (h - y0 - 0.04) / rows
	Kit.box(g, Vector3(w - 0.08, h - 0.07, 0.02), Vector3(0, h * 0.5, -d * 0.5 + 0.01), wood.darkened(0.3))
	for i in cols + 1:
		Kit.block(g, Vector3(0.04 if i == 0 or i == cols else 0.025, h if i == 0 or i == cols else h - y0 - 0.04, d), Vector3(-w * 0.5 + 0.02 + i * cw, 0.0 if i == 0 or i == cols else y0, 0), wood)
	for k in rows + 1:
		Kit.box(g, Vector3(w - 0.04, 0.025 if k < rows else 0.04, d), Vector3(0, y0 + k * ch, 0), wood)
	Kit.block(g, Vector3(w - 0.1, y0 - 0.0125, d - 0.08), Vector3(0, 0, -0.015), DARK)
	for c in cols:
		for r in rows:
			var key := u * 2.1 + v * 1.3 + c * 3.7 + r * 1.9
			var look: Color = DENIM[c % DENIM.size()]
			look = look.darkened(0.08) if r % 2 == 1 else look
			var x := -w * 0.5 + 0.02 + (c + 0.5) * cw
			var layers := 4 + int(Props.rnd(key) * 3.0)
			for k in layers:
				var y := y0 + r * ch + 0.0125 + k * 0.058
				Kit.block(g, Vector3(cw - 0.08, 0.052, 0.3), Vector3(x + 0.012 * (Props.rnd(key + k) - 0.5), y, 0.03 + 0.01 * Props.rnd(key + k + 0.5)), look.lightened(0.07) if k % 2 == 0 else look)
	Props.sign_box(g, "DENIM", Vector3(0, 2.6, -d * 0.5 + 0.07), Vector2(1.2, 0.32), Color(0.16, 0.24, 0.52), WHITE, 0.0, 0.5)
	spots(g, [-0.82, 0.82], 2.66, -d * 0.5)
	return g


# --------------------------------------------------------------- sneakers

## A chunky sneaker, its toe to +x, the bottom of its sole at `pos`.
static func sneaker(parent: Node3D, pos: Vector3, yaw: float, upper: Color, trim: Color, sole := WHITE) -> Node3D:
	var g := Kit.group(parent, pos, Vector3(0, yaw, 0))
	Kit.block(g, Vector3(0.3, 0.045, 0.11), Vector3.ZERO, sole)
	Kit.block(g, Vector3(0.2, 0.085, 0.1), Vector3(-0.04, 0.045, 0), upper)
	Kit.block(g, Vector3(0.1, 0.05, 0.095), Vector3(0.095, 0.045, 0), upper)
	Kit.block(g, Vector3(0.08, 0.04, 0.104), Vector3(-0.1, 0.11, 0), trim)
	Kit.box(g, Vector3(0.14, 0.035, 0.104), Vector3(0.0, 0.08, 0), trim)
	Kit.block(g, Vector3(0.09, 0.02, 0.07), Vector3(0.02, 0.124, 0), upper.lightened(0.15) if upper != WHITE else Color(0.86, 0.86, 0.84))
	return g


## A shoe box, end on (its end to +z), the middle of its bottom at `pos`.
static func shoe_box(parent: Node3D, pos: Vector3, key: float) -> void:
	var pair: Array = pick(BOXES, key)
	Kit.block(parent, Vector3(0.2, 0.12, 0.33), pos, pair[0])
	Kit.block(parent, Vector3(0.206, 0.04, 0.336), pos + Vector3(0, 0.085, 0), pair[1])
	Kit.box(parent, Vector3(0.09, 0.035, 0.004), pos + Vector3(0, 0.045, 0.167), WHITE)


## The sneaker wall: one shoe on each little shelf in a grid, the boxes stacked
## underneath, a lit KICKS sign on top. Its back on the wall.
static func sneaker_wall(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 2.6) -> Node3D:
	var d := 0.4
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	var back := -d * 0.5
	var panel := Color(0.1, 0.1, 0.12)
	Kit.box(g, Vector3(w, 1.78, 0.03), Vector3(0, 1.57, back + 0.015), panel)
	Kit.box(g, Vector3(w + 0.06, 0.05, 0.05), Vector3(0, 2.485, back + 0.025), CHROME)
	var front := back + 0.03
	var cols := maxi(int(w / 0.43), 1)
	for r in 4:
		for c in cols:
			var key := u * 1.7 + v * 2.9 + r * 5.3 + c * 1.1
			var x := -w * 0.5 + (c + 0.5) * w / cols
			var y := 0.98 + r * 0.37
			Kit.box(g, Vector3(0.34, 0.02, 0.2), Vector3(x, y - 0.01, front + 0.1), CLEAR)
			Kit.box(g, Vector3(0.02, 0.06, 0.02), Vector3(x, y - 0.05, front + 0.01), CHROME)
			var pair: Array = pick(KICKS, key)
			sneaker(g, Vector3(x, y, front + 0.1), -14.0, pair[0], pair[1], Color(0.62, 0.42, 0.24) if Props.rnd(key + 7.0) > 0.85 else WHITE)
	# The boxes, five high.
	var n := int((w - 0.02) / 0.215)
	for c in n:
		for r in 5:
			shoe_box(g, Vector3(-n * 0.1075 + 0.1075 + c * 0.215, r * 0.125, front + 0.17), u * 0.9 + v * 1.3 + c * 3.1 + r * 1.7)
	Props.sign_box(g, "KICKS", Vector3(0, 2.68, back + 0.07), Vector2(1.2, 0.32), Color(0.95, 0.95, 0.92), Color(0.86, 0.14, 0.12), 0.0, 0.6)
	spots(g, [-0.85, 0.85], 2.72, back)
	return g


## The try-on bench: a padded seat, a box and a sneaker on it, a foot measure on the floor.
static func try_bench(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.3) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.45)
	Kit.block(g, Vector3(w, 0.32, 0.4), Vector3.ZERO, Props.WOOD_DARK)
	Kit.block(g, Vector3(w + 0.04, 0.12, 0.44), Vector3(0, 0.32, 0), Color(0.72, 0.1, 0.12))
	for i in 3:
		Kit.box(g, Vector3(0.012, 0.004, 0.42), Vector3(-w * 0.25 + i * w * 0.25, 0.442, 0), Color(0.5, 0.06, 0.08))
	shoe_box(g, Vector3(-w * 0.05, 0.44, 0.0), u * 7.0 + 1.0)
	sneaker(g, Vector3(-w * 0.32, 0.44, 0.05), 20.0, WHITE, Color(0.14, 0.3, 0.82))
	# The foot measure: a steel plate with a slide, flat on the floor in front.
	Kit.block(g, Vector3(0.13, 0.02, 0.32), Vector3(-w * 0.25, 0.0, 0.42), Props.STEEL)
	Kit.block(g, Vector3(0.11, 0.025, 0.04), Vector3(-w * 0.25, 0.0, 0.33), DARK)
	return g


## The slanted foot mirror that stands on the floor, leaning back (against the
## front of a try-on bench): stand in front of it and look down at your shoes.
static func foot_mirror(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.48, 0.46)
	Kit.block(g, Vector3(0.46, 0.04, 0.22), Vector3(0, 0, 0.08), DARK)
	var lean := Kit.group(g, Vector3(0, 0.02, 0.0), Vector3(-24, 0, 0))
	Kit.block(lean, Vector3(0.46, 0.5, 0.035), Vector3.ZERO, DARK)
	Kit.box(lean, Vector3(0.39, 0.43, 0.01), Vector3(0, 0.25, 0.019), Kit.flat(MIRROR, 0.3))
	Kit.box(lean, Vector3(0.035, 0.32, 0.004), Vector3(-0.07, 0.26, 0.026), Color(1, 1, 1, 0.55), Vector3(0, 0, -30))
	Kit.box(lean, Vector3(0.015, 0.22, 0.004), Vector3(0.02, 0.26, 0.026), Color(1, 1, 1, 0.45), Vector3(0, 0, -30))
	return g


# ----------------------------------------------------------------- shirts

## A stack of folded T-shirts, `n` high, the bottom at `pos`; the top one has a print.
static func tee_stack(parent: Node3D, pos: Vector3, look: Color, n: int, key: float) -> void:
	for k in n:
		Kit.block(parent, Vector3(0.3, 0.045, 0.26), pos + Vector3(0.012 * (Props.rnd(key + k) - 0.5), k * 0.046, 0), look.darkened(0.06) if k % 2 == 1 else look)
	var print_look: Color = pick(LOUD, key + 9.0)
	if print_look == look:
		print_look = WHITE if look != WHITE else DARK
	Kit.box(parent, Vector3(0.13, 0.004, 0.11), pos + Vector3(0, n * 0.046 + 0.001, 0.0), print_look)


## The shirt table: a chunky low table of folded tees in every colour, and a
## card on a stand.
static func shirt_table(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.6, d := 0.8) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	var h := 0.76
	Kit.block(g, Vector3(w - 0.2, h - 0.06, d - 0.2), Vector3.ZERO, DARK)
	Kit.block(g, Vector3(w, 0.06, d), Vector3(0, h - 0.06, 0), Color(0.9, 0.88, 0.84))
	Kit.block(g, Vector3(w - 0.1, 0.04, d - 0.1), Vector3(0, 0, 0), DARK.lightened(0.1))
	var cols := maxi(int(w / 0.38), 1)
	for c in cols:
		for r in 2:
			var key := u * 4.1 + v * 2.3 + c * 3.3 + r * 7.7
			tee_stack(g, Vector3(-w * 0.5 + (c + 0.5) * w / cols, h, (r - 0.5) * d * 0.48), pick(LOUD, key), 3 + int(Props.rnd(key + 1.0) * 4.0), key)
	var card := Kit.group(g, Vector3(w * 0.5 - 0.12, h, d * 0.5 - 0.08), Vector3(-15, -20, 0))
	Kit.block(card, Vector3(0.22, 0.16, 0.012), Vector3.ZERO, WHITE)
	Props.words(card, "2 FOR $15", Vector3(0, 0.08, 0.008), 0.035, Color(0.86, 0.14, 0.12))
	return g


## A jersey hanging face-out (its front to +z) from a hanger at `top`: a
## basketball tank with a contrasting trim and, if given, a number.
static func jersey(parent: Node3D, top: Vector3, look: Color, trim: Color, number := "") -> void:
	var y0 := top.y - 0.05
	Kit.box(parent, Vector3(0.012, 0.06, 0.012), Vector3(top.x, top.y - 0.01, top.z), Props.STEEL)
	Kit.box(parent, Vector3(0.4, 0.46, 0.03), Vector3(top.x, y0 - 0.1 - 0.23, top.z), look)
	for s: float in [-1.0, 1.0]:
		Kit.box(parent, Vector3(0.09, 0.11, 0.03), Vector3(top.x + s * 0.13, y0 - 0.055, top.z), look)
		Kit.box(parent, Vector3(0.016, 0.16, 0.034), Vector3(top.x + s * 0.18, y0 - 0.13, top.z), trim)
	Kit.box(parent, Vector3(0.412, 0.03, 0.036), Vector3(top.x, y0 - 0.545, top.z), trim)
	Kit.box(parent, Vector3(0.12, 0.025, 0.034), Vector3(top.x, y0 - 0.11, top.z), trim)
	if number != "":
		Props.words(parent, number, Vector3(top.x, y0 - 0.33, top.z + 0.018), 0.17, trim)


## The jersey stand: a low chrome stand with two arms, jerseys face-out down
## each arm. Under 1.3 m, for the middle of the floor.
static func jersey_rack(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.1, 0.6)
	Kit.block(g, Vector3(0.9, 0.03, 0.06), Vector3(0, 0, -0.22), CHROME)
	for s: float in [-1.0, 1.0]:
		Kit.block(g, Vector3(0.05, 0.03, 0.5), Vector3(s * 0.42, 0, 0.0), CHROME)
		Kit.cyl(g, 0.018, 1.24, Vector3(s * 0.42, 0.63, -0.22), CHROME, Vector3.ZERO, 6)
	Kit.box(g, Vector3(0.9, 0.025, 0.025), Vector3(0, 1.24, -0.22), CHROME)
	var numbers := ["12", "8", "33", "1"]
	for s in 2:
		var x := -0.24 + s * 0.48
		Kit.box(g, Vector3(0.025, 0.025, 0.5), Vector3(x, 1.24, 0.02), CHROME)
		for k in 4:
			var key := u * 1.9 + v * 3.1 + s * 5.3 + k * 1.7
			var look: Color = pick(LOUD, key)
			var trim: Color = pick(LOUD, key + 2.0)
			if trim == look:
				trim = WHITE if look != WHITE else DARK
			jersey(g, Vector3(x, 1.24, -0.16 + k * 0.1), look, trim, numbers[s * 2 + (k % 2)] if k == 3 else "")
	return g


## A round rack of tracksuit tops and windbreakers, hung all the way round a
## chrome ring. Under 1.3 m, for the middle of the floor.
static func round_rack(p: Node3D, b: int, u: float, v: float, r := 0.38) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, r * 2.0 + 0.44, r * 2.0 + 0.44)
	Kit.cyl(g, 0.3, 0.04, Vector3(0, 0.02, 0), CHROME, Vector3.ZERO, 12)
	Kit.cyl(g, 0.025, 1.2, Vector3(0, 0.62, 0), CHROME, Vector3.ZERO, 6)
	Kit.ring(g, r + 0.012, 0.024, Vector3(0, 1.2, 0), CHROME, Vector3(-90, 0, 0))
	for k in 2:
		Kit.box(g, Vector3(r * 2.0, 0.02, 0.02), Vector3(0, 1.2, 0), CHROME, Vector3(0, 45.0 + k * 90.0, 0))
	# Track tops packed on hangers round the ring, sorted into runs of one
	# colour as a shop keeps them; every other run has a white stripe.
	var n := 28
	for i in n:
		var a := TAU * (float(i) + 0.5) / float(n)
		var run := i / 4
		var look: Color = pick(LOUD, u * 2.3 + v * 1.1 + run * 3.7)
		var trim: Color = WHITE if run % 2 == 0 else DARK
		var hang := Kit.group(g, Vector3(sin(a) * r, 1.2, cos(a) * r), Vector3(0, rad_to_deg(a), 0))
		Kit.box(hang, Vector3(0.012, 0.06, 0.012), Vector3(0, -0.01, 0), Props.STEEL)
		Kit.box(hang, Vector3(0.016, 0.02, 0.3), Vector3(0, -0.045, 0), DARK)
		Kit.box(hang, Vector3(0.07, 0.6, 0.34), Vector3(0, -0.36, 0), look)
		Kit.box(hang, Vector3(0.074, 0.585, 0.04), Vector3(0, -0.365, 0.12), trim)
		Kit.box(hang, Vector3(0.076, 0.05, 0.344), Vector3(0, -0.638, 0), look.darkened(0.3))
	return g


# ------------------------------------------------------------- the counter

## Sunglasses, folded, facing +z, the bottom at `pos`.
static func shades(parent: Node3D, pos: Vector3, frame: Color, lens: Color, yaw := 0.0) -> void:
	var g := Kit.group(parent, pos, Vector3(0, yaw, 0))
	for s: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(0.058, 0.04, 0.012), Vector3(s * 0.034, 0.02, 0), lens)
	Kit.box(g, Vector3(0.14, 0.012, 0.016), Vector3(0, 0.044, 0), frame)
	Kit.box(g, Vector3(0.12, 0.008, 0.07), Vector3(0, 0.03, -0.04), frame)


## The glass counter: a lit case of gold chains, rings and sunglasses on dark
## velvet, chrome edges, the till on top. Its front (+z) is the customer's side.
static func glass_counter(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 2.0, d := 0.6) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	var base := Color(0.16, 0.15, 0.2)
	Kit.block(g, Vector3(w, 0.3, d), Vector3.ZERO, base)
	Kit.box(g, Vector3(w - 0.02, 0.06, 0.012), Vector3(0, 0.15, d * 0.5 + 0.004), Color(0.5, 0.2, 0.66))
	Kit.block(g, Vector3(w - 0.06, 0.02, d - 0.06), Vector3(0, 0.3, 0), Color(0.18, 0.08, 0.2))
	Kit.box(g, Vector3(w - 0.1, 0.64, 0.02), Vector3(0, 0.64, -d * 0.5 + 0.03), Props.WOOD_DARK)
	Kit.box(g, Vector3(w - 0.04, 0.64, 0.012), Vector3(0, 0.64, d * 0.5 - 0.02), Props.GLASS)
	for s: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(0.012, 0.64, d - 0.04), Vector3(s * (w * 0.5 - 0.02), 0.64, 0), Props.GLASS)
		for t: float in [-1.0, 1.0]:
			Kit.box(g, Vector3(0.03, 0.66, 0.03), Vector3(s * (w * 0.5 - 0.015), 0.63, t * (d * 0.5 - 0.015)), CHROME)
	Kit.box(g, Vector3(w, 0.03, d), Vector3(0, 0.975, 0), CLEAR)
	Kit.box(g, Vector3(w + 0.02, 0.03, 0.03), Vector3(0, 0.99, d * 0.5 - 0.012), CHROME)
	Kit.omni(g, Vector3(0, 0.8, 0.1), Color(1.0, 0.92, 0.75), 0.25, 1.4)
	# Up on a glass shelf, the sunglasses; on the velvet, the chains and rings.
	Kit.box(g, Vector3(w - 0.12, 0.01, d * 0.45), Vector3(0, 0.62, -0.06), CLEAR)
	var n := int((w - 0.2) / 0.19)
	for i in n:
		var key := u * 3.3 + i * 1.7
		shades(g, Vector3(-w * 0.5 + 0.2 + i * 0.19, 0.625, -0.02), pick([DARK, GOLD, WHITE, Color(0.86, 0.14, 0.12)], key), pick([DARK, Color(0.2, 0.35, 0.3), Color(0.5, 0.25, 0.1), Color(0.25, 0.2, 0.5)], key + 1.0), 6.0 * (Props.rnd(key + 2.0) - 0.5))
	for i in n:
		var x := -w * 0.5 + 0.22 + i * 0.19
		var gold := Kit.flat(GOLD, 0.25)
		if i % 3 == 2:
			for k in 3:
				Kit.ring(g, 0.022, 0.008, Vector3(x - 0.05 + k * 0.05, 0.33, 0.1), gold, Vector3(-75, 0, 0))
		else:
			Kit.ring(g, 0.085 - 0.02 * (i % 2), 0.011, Vector3(x, 0.325, 0.08), gold, Vector3(-82, 0, 0))
			Kit.box(g, Vector3(0.04, 0.008, 0.05), Vector3(x, 0.325, 0.08 + 0.085), gold, Vector3(0, 45, 0))
	Props.till(g, Vector3(0.5, 0.99, -0.08), 180.0)
	return g


## A round shoplifting mirror on a bracket, high in a corner, tipped down.
static func security_mirror(parent: Node3D, pos: Vector3, yaw := 0.0) -> Node3D:
	var g := Kit.group(parent, pos, Vector3(0, yaw, 0))
	Kit.box(g, Vector3(0.04, 0.04, 0.32), Vector3(0, 0, 0.16), Props.IRON)
	var tip := Kit.group(g, Vector3(0, -0.04, 0.34), Vector3(22, 0, 0))
	var dome := Kit.ball(tip, 0.26, Vector3.ZERO, Kit.flat(Color(0.72, 0.78, 0.84), 0.25), 14)
	dome.scale = Vector3(1, 1, 0.32)
	Kit.ring(tip, 0.27, 0.025, Vector3(0, 0, -0.01), DARK)
	Kit.ball(tip, 0.06, Vector3(-0.08, 0.09, 0.07), Color(1, 1, 1, 0.6), 8)
	return g


# ----------------------------------------------------------------- dummies

## A window dummy dressed in an outfit: jeans (or khakis) on two legs, a puffer
## on its torso, a sneaker on each foot, a cap on its faceless head (worn
## backwards if `backwards`). Its feet at `pos`, facing +z turned by `yaw`.
static func mannequin(parent: Node3D, pos: Vector3, yaw: float, shell: Color, trim: Color, hat: Color, legs: Color, kicks: Array, backwards := false, hood := false) -> Node3D:
	var g := Kit.group(parent, pos, Vector3(0, yaw, 0))
	var form := Color(0.92, 0.9, 0.86)
	Kit.cyl(g, 0.24, 0.035, Vector3(0, 0.0175, 0), CHROME, Vector3.ZERO, 14)
	for s: float in [-1.0, 1.0]:
		sneaker(g, Vector3(s * 0.1, 0.035, 0.045), -90.0, kicks[0], kicks[1])
		Kit.block(g, Vector3(0.15, 0.78, 0.17), Vector3(s * 0.1, 0.17, 0), legs.darkened(0.05 if s > 0.0 else 0.0))
		Kit.block(g, Vector3(0.17, 0.06, 0.19), Vector3(s * 0.1, 0.13, 0), legs.darkened(0.12))
	Kit.block(g, Vector3(0.38, 0.16, 0.18), Vector3(0, 0.92, 0), legs)
	puffer_front(g, Vector3(0, 1.66, 0), shell, trim, hood, true, 0.24, 0.46, 0.66)
	Kit.cyl(g, 0.05, 0.1, Vector3(0, 1.65, 0), form, Vector3.ZERO, 8)
	var head := Kit.ball(g, 0.12, Vector3(0, 1.8, 0), form, 12)
	head.scale = Vector3(1, 1.12, 1)
	var lid := cap(g, Vector3(0, 1.83, 0.0), hat, hat.darkened(0.2), 0.0)
	lid.rotation_degrees = Vector3(-6, 180.0 if backwards else 0.0, 0)
	lid.scale = Vector3.ONE * 1.28
	return g


# ---------------------------------------------------------- fitting rooms

## A curtain from x0 to x1 hanging from `top` to `bottom` at z, in folds; drawn
## back, it is bunched up at x0.
static func _curtain(g: Node3D, x0: float, x1: float, top: float, bottom: float, z: float, cloth: Color, drawn := false) -> void:
	var to := x1
	if drawn:
		to = x0 + (x1 - x0) * 0.24
	var n := maxi(int((to - x0) / (0.06 if drawn else 0.13)), 2)
	var sw := (to - x0) / n
	var deep := 0.03 if drawn else 0.012
	for i in n:
		Kit.box(g, Vector3(sw, top - bottom, 0.02), Vector3(x0 + (i + 0.5) * sw, (top + bottom) * 0.5, z + (deep if i % 2 == 0 else -deep)), cloth.darkened(0.16 * (i % 2)))


## A row of n fitting booths against a wall: partitions, a fascia with the
## numbers, a curtain across each front (booth `open` has its curtain drawn
## back), and inside a mirror, a hook and a stool. Someone's sneakers show
## under the curtain of booth `busy`.
static func fitting_booths(p: Node3D, b: int, u: float, v: float, yaw := 0.0, n := 3, bw := 1.2, d := 1.3, cloth := Color(0.55, 0.1, 0.24), open := 0, busy := 2) -> Node3D:
	var w := bw * n
	var g: Node3D = p.prop(b, u, v, yaw, w, d)
	var board := Color(0.92, 0.88, 0.8)
	var back := -d * 0.5
	for i in n + 1:
		var x := clampf(-w * 0.5 + i * bw, -w * 0.5 + 0.025, w * 0.5 - 0.025)
		Kit.block(g, Vector3(0.05, 2.12, d - 0.02), Vector3(x, 0.0, -0.01), board.darkened(0.08))
	Kit.box(g, Vector3(w, 0.26, 0.06), Vector3(0, 2.25, d * 0.5 - 0.04), board)
	for i in n:
		var x := -w * 0.5 + (i + 0.5) * bw
		Props.words(g, str(i + 1), Vector3(x, 2.25, d * 0.5 - 0.004), 0.17, Color(0.55, 0.1, 0.24))
		Kit.box(g, Vector3(0.48, 1.16, 0.012), Vector3(x + 0.12, 1.3, back + 0.006), DARK)
		Kit.box(g, Vector3(0.42, 1.1, 0.012), Vector3(x + 0.12, 1.3, back + 0.014), Kit.flat(MIRROR, 0.3))
		Kit.box(g, Vector3(0.025, 0.025, 0.12), Vector3(x - 0.32, 1.72, back + 0.06), CHROME)
		Kit.cyl(g, 0.17, 0.04, Vector3(x - 0.25, 0.46, back + 0.45), Props.WOOD, Vector3.ZERO, 10)
		Kit.cyl(g, 0.025, 0.44, Vector3(x - 0.25, 0.22, back + 0.45), CHROME, Vector3.ZERO, 6)
		Kit.cyl(g, 0.15, 0.02, Vector3(x - 0.25, 0.01, back + 0.45), CHROME, Vector3.ZERO, 10)
		if i == open:
			jersey(g, Vector3(x - 0.32, 1.74, back + 0.1), Color(0.98, 0.76, 0.1), Color(0.14, 0.3, 0.82), "")
			for k in 3:
				Kit.block(g, Vector3(0.26, 0.05, 0.22), Vector3(x - 0.25, 0.48 + k * 0.05, back + 0.45), DENIM[k].lightened(0.05 * (k % 2)))
		Kit.box(g, Vector3(bw - 0.07, 0.025, 0.025), Vector3(x, 2.1, d * 0.5 - 0.1), CHROME)
		_curtain(g, x - bw * 0.5 + 0.035, x + bw * 0.5 - 0.035, 2.09, 0.24, d * 0.5 - 0.1, cloth, i == open)
		if i == busy:
			for s: float in [-1.0, 1.0]:
				sneaker(g, Vector3(x + s * 0.09, 0.0, d * 0.5 - 0.3), -80.0 + s * 8.0, WHITE, Color(0.86, 0.14, 0.12))
	return g


## One framed mirror panel `w` wide and `h` tall, standing on the floor with
## its back at `at`, facing +z.
static func _mirror_panel(g: Node3D, at: Vector3, w: float, h: float, frame: Color) -> void:
	Kit.block(g, Vector3(w, h, 0.04), at + Vector3(0, 0.08, 0.02), frame)
	Kit.box(g, Vector3(w - 0.08, h - 0.08, 0.01), at + Vector3(0, 0.08 + h * 0.5, 0.045), Kit.flat(MIRROR, 0.32))
	Kit.box(g, Vector3(0.05, h * 0.42, 0.004), at + Vector3(-w * 0.16, 0.08 + h * 0.62, 0.052), Color(1, 1, 1, 0.5), Vector3(0, 0, -28))
	Kit.box(g, Vector3(0.022, h * 0.3, 0.004), at + Vector3(-w * 0.02, 0.08 + h * 0.6, 0.052), Color(1, 1, 1, 0.4), Vector3(0, 0, -28))
	for s: float in [-1.0, 1.0]:
		Kit.block(g, Vector3(0.06, 0.08, 0.22), at + Vector3(s * (w * 0.5 - 0.06), 0, 0.08), frame.darkened(0.3))


## A tall framed mirror hung on a wall, its bottom at 0.3 m.
static func wall_mirror(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 0.6, h := 1.7) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.05, false)
	Kit.box(g, Vector3(w, h, 0.02), Vector3(0, 0.3 + h * 0.5, 0.0), Color(0.78, 0.6, 0.22))
	Kit.box(g, Vector3(w - 0.08, h - 0.08, 0.01), Vector3(0, 0.3 + h * 0.5, 0.012), Kit.flat(MIRROR, 0.32))
	Kit.box(g, Vector3(0.05, h * 0.4, 0.004), Vector3(-w * 0.16, 0.3 + h * 0.62, 0.02), Color(1, 1, 1, 0.5), Vector3(0, 0, -28))
	Kit.box(g, Vector3(0.022, h * 0.28, 0.004), Vector3(-w * 0.02, 0.3 + h * 0.6, 0.02), Color(1, 1, 1, 0.4), Vector3(0, 0, -28))
	return g


## A tall three-way mirror: a middle panel and two wings turned in towards
## whoever stands in front of it.
static func three_way_mirror(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.3, 0.45)
	var frame := Color(0.78, 0.6, 0.22)
	var back := -0.2
	_mirror_panel(g, Vector3(0, 0, back), 0.64, 1.95, frame)
	for s: float in [-1.0, 1.0]:
		var wing := Kit.group(g, Vector3(s * 0.33, 0, back + 0.01), Vector3(0, -s * 38.0, 0))
		_mirror_panel(wing, Vector3(s * 0.2, 0, 0), 0.4, 1.8, frame)
	Kit.box(g, Vector3(0.54, 0.05, 0.05), Vector3(0, 2.055, back + 0.02), frame.darkened(0.2))
	Kit.box(g, Vector3(0.46, 0.04, 0.05), Vector3(0, 2.1, back + 0.03), Kit.flat(Color(1.0, 0.95, 0.8), 1.2))
	return g


# -------------------------------------------------------------- stock room

## A rolling rail of new stock in clear plastic bags.
static func garment_rack(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 1.5) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.55)
	for s: float in [-1.0, 1.0]:
		var x := s * (w * 0.5 - 0.03)
		Kit.box(g, Vector3(0.03, 1.62, 0.03), Vector3(x, 0.89, 0), CHROME)
		Kit.box(g, Vector3(0.04, 0.03, 0.5), Vector3(x, 0.075, 0), CHROME)
		for t: float in [-1.0, 1.0]:
			Kit.cyl(g, 0.03, 0.03, Vector3(x, 0.03, t * 0.22), DARK, Vector3(0, 0, 90), 8)
	Kit.cyl(g, 0.015, w, Vector3(0, 1.7, 0), CHROME, Vector3(0, 0, 90), 6)
	var n := int((w - 0.2) / 0.09)
	for i in n:
		var x := -w * 0.5 + 0.12 + i * (w - 0.24) / float(n - 1)
		Kit.box(g, Vector3(0.012, 0.06, 0.012), Vector3(x, 1.7, 0), Props.STEEL)
		Kit.box(g, Vector3(0.06, 0.95, 0.42), Vector3(x, 1.165, 0), pick(LOUD, x * 3.1 + u))
		Kit.box(g, Vector3(0.075, 1.05, 0.46), Vector3(x, 1.13, 0), Color(0.9, 0.93, 0.95, 0.35))
	return g


## Shoe boxes stacked end on, `cols` columns of up to `rows`.
static func shoe_boxes(p: Node3D, b: int, u: float, v: float, yaw := 0.0, cols := 4, rows := 6) -> Node3D:
	var w := cols * 0.215
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.36)
	for c in cols:
		for r in rows - int(Props.rnd(u + c * 1.7) * 2.5):
			shoe_box(g, Vector3(-w * 0.5 + 0.1075 + c * 0.215, r * 0.125, 0.0), u * 3.3 + v * 1.9 + c * 5.1 + r * 2.7)
	return g


## Open shelving with shoe boxes stacked on every shelf (the sizes behind a counter).
static func box_shelves(p: Node3D, b: int, u: float, v: float, yaw := 0.0, w := 2.0, h := 1.9) -> Node3D:
	var g: Node3D = Props.shelves(p, b, u, v, yaw, w, "none", Props.IRON, h, 0.38)
	var cols := int((w - 0.1) / 0.215)
	for i in 4:
		var y := 0.1 + i * (h - 0.14) / 4.0 + 0.015
		for c in cols:
			for r in 3:
				shoe_box(g, Vector3(-cols * 0.1075 + 0.1075 + c * 0.215, y + r * 0.125, 0.0), u * 1.1 + i * 7.3 + c * 2.9 + r * 1.3)
	return g
