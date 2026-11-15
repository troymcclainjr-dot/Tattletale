extends RefCounted
## The pop-up's Pen Lucy houses: one kit for the outside of every home, so the
## crib's row, Miss Bea's row, Large Fry's block, the neighbours beside the shops
## (Props.rowhouse), the backs across the park's alley, Linden Square and Rose
## Hill Terrace all belong to the same streets. Copied from the old game's house
## kits (blender/city/kits.py: KIT_MATS, style(), the window, door, porch and
## cornice kits; process.py: the archetypes, alternating doors, storeys; facade
## v2: bays and oriels; see plans/street.gd for Rose Hill's measured street),
## built the pop-up's way: chunky boxes, flat colours, fat-texel brick and
## formstone.
##
## A house front is built on a FACE: a group standing at the front's left end
## (as seen from in front of it), its x running along the front to the right,
## its y up and its z pointing out of the wall. `fb` puts a box on a face from
## its ranges (s along, y up, t out), so a house can be stood facing any way.
##
##   const Houses := preload("res://scripts/houses.gd")
##   var g := Houses.face(p, band, u0, v)            # or Kit.group(node, p.pt(u0, v))
##   Houses.stoop_front(g, 5.0, Houses.style(key))   # a stoop-front rowhouse
##   Houses.porch_front(g, 6.4, {"wall": Houses.wall("brick"), ...})
##
## The old game's two row types:
##   porch_front  the porch-front row (692 of its thousand-odd houses): an open
##                porch the width of the house on a deck, posts, a railing and
##                a flat roof; a canted sash bay upstairs on the porch roof.
##   stoop_front  the stoop-front row: marble steps up to the door, sashes with
##                lintels, a box oriel upstairs on a quarter of them, tin
##                awnings over the upstairs windows on a quarter.
## Its rows share a brick and a cornice; each house picks its own trim, door,
## lintels, chimney, and now and then formstone or paint (`style`), and the
## doors alternate so neighbours mirror in pairs.

const Props := preload("res://scripts/props.gd")
const Outdoor := preload("res://scripts/outdoor.gd")

const WHITE := Color(0.96, 0.94, 0.9)           # trim_white (244, 240, 230)
const CREAM := Color(0.9, 0.84, 0.71)           # trim_cream (226, 212, 180)
const BROWN := Color(0.4, 0.26, 0.18)           # trim_brown (90, 58, 40)
const RED := Color(0.6, 0.18, 0.15)             # trim_red (138, 42, 36)
const GREEN := Color(0.27, 0.4, 0.3)            # trim_green (63, 90, 68)
const DOORS := {
	"red": Color(0.62, 0.16, 0.14), "green": Color(0.2, 0.34, 0.24), "blue": Color(0.2, 0.28, 0.46),
	"black": Color(0.12, 0.11, 0.11), "wood": Color(0.46, 0.3, 0.17), "white": Color(0.91, 0.89, 0.85),
}
const PORCH := Color(0.56, 0.56, 0.59)          # deck and steps (138, 138, 144)
const PORCH_ROOF := Color(0.45, 0.37, 0.3)      # (106, 88, 70)
const TAR := Color(0.27, 0.27, 0.3)             # roof_tar (62, 62, 68)
const SILVER := Color(0.62, 0.62, 0.65)         # roof_silver (168, 168, 174), the silver-coated flat roofs
const BASE := Color(0.6, 0.59, 0.55)            # the grey base course
const MARBLE := Color(0.94, 0.93, 0.89)         # (238, 234, 224)
const CONCRETE := Color(0.72, 0.71, 0.68)       # (182, 178, 166)
const STONE := Color(0.72, 0.71, 0.68)          # formstone lintels and copings
const PANE := Color(0.11, 0.14, 0.2)            # glass (26, 34, 48)
const IRON := Color(0.12, 0.12, 0.14)
const SHUTTER := Color(0.33, 0.34, 0.36)        # shutter_dark (92, 94, 98): hoods, AC louvres
const BARS := Color(0.16, 0.16, 0.18)           # bars_dark (44, 44, 48): leaders, brackets
const GRIME := Color(0.33, 0.29, 0.25)          # (90, 80, 68)
const PLY := Color(0.55, 0.42, 0.26)            # plywood over a vacant's door and windows
const LIT := Color(1.0, 0.8, 0.48)
const TV := Color(0.55, 0.72, 1.0)
const GOLD := Color(0.95, 0.78, 0.3)
## The tin window awnings: red, green, brown, white (156, 59, 48 and so on).
const TIN := [Color(0.61, 0.23, 0.19), Color(0.24, 0.42, 0.3), Color(0.43, 0.3, 0.2), Color(0.86, 0.86, 0.82)]

const F0 := 0.7              # the ground floor (and the porch deck) above the pavement
const CEIL := 3.8            # the porch ceiling
const PROOF := 4.0           # the top of the porch roof: 3.3 above the deck
const PD := 2.0              # how deep the porch is
const RISE := 0.175          # a step's rise

## Rose Hill's three upper bays: width, how far it stands out, half the front's share of the width.
const BAYS := {"white": [2.25, 0.64, 0.29], "cream": [2.05, 0.52, 0.32], "grey": [2.35, 0.72, 0.27]}


# ------------------------------------------------------------------ faces

## A face at (u, v) on the plan: `yaw` as for props (0 the front faces the
## street, +z; 90 it faces right; 270 left).
static func face(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	return Kit.group(p.node_of(b), p.pt(u, v), Vector3(0, yaw, 0))


## A face along the line a to b on another face (s, t on that face). Its z
## points out to the left of the way from a to b.
static func sub_face(g: Node3D, a: Vector2, b: Vector2) -> Node3D:
	var d := b - a
	return Kit.group(g, Vector3(a.x, 0, a.y), Vector3(0, rad_to_deg(atan2(-d.y, d.x)), 0))


## A box on a face: s0..s1 along it, y0..y1 up, t0..t1 out of it (negative is into the wall).
static func fb(g: Node3D, s0: float, s1: float, y0: float, y1: float, t0: float, t1: float, look: Variant) -> MeshInstance3D:
	return Kit.box(g, Vector3(s1 - s0, y1 - y0, t1 - t0), Vector3((s0 + s1) * 0.5, (y0 + y1) * 0.5, (t0 + t1) * 0.5), look)


## A round bar from a to b (rails, wires, a lamp's arm).
static func pipe(g: Node3D, a: Vector3, b: Vector3, r: float, look: Variant, sides := 6) -> MeshInstance3D:
	var mi := Kit.cyl(g, r, a.distance_to(b), (a + b) * 0.5, look, Vector3.ZERO, sides)
	var y := (b - a).normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	mi.basis = Basis(x, y, x.cross(y))
	return mi


# ------------------------------------------------------------- materials

## A wall material by the old game's names: "brick" (154, 90, 68), "brick_2"
## (138, 74, 58), "brick_3" (168, 100, 74), "brick_dark" (110, 58, 48),
## "formstone" (154, 150, 140), "formstone_tan" (180, 166, 138), "painted"
## (216, 208, 192, painted brick). The brick and formstone are Rose Hill's.
static func wall(kind: String) -> Material:
	match kind:
		"formstone":
			return Outdoor.tex("out_formstone", 2.0, Color(0.6, 0.59, 0.55), Color(1.0, 1.0, 1.0))
		"formstone_tan":
			return Outdoor.tex("out_formstone", 2.0, Color(0.7, 0.65, 0.54), Color(1.0, 0.92, 0.76))
		"painted":
			return Kit.tex("painted_block", 0.7, Color(0.71, 0.65, 0.54), true, Color(0.8, 0.78, 0.98))
		"brick_2":
			return brick(Color(0.84, 0.78, 0.8))
		"brick_3":
			return brick(Color(1.0, 0.97, 0.93))
		"brick_dark":
			return brick(Color(0.7, 0.62, 0.66))
	return brick(Color(0.93, 0.88, 0.87))


## Rose Hill's brick, tinted.
static func brick(tint: Color) -> Material:
	return Kit.tex("brick", 1.5, Color(0.54, 0.29, 0.23), true, tint)


## A number from 0 to 1 for this house and this choice.
static func _r(key: float, i: int) -> float:
	return Props.rnd(key * 3.17 + float(i) * 1.913)


## One house's own look, as the old game's style() picks it: the row's wall
## (`row_wall`) or, now and then, formstone (12 in 100), tan formstone (6) or
## paint (7); the trim (white half the time, cream, green, brown, red); a door
## colour; a lintel over the windows on 60 in 100 brick fronts (white, cream or
## formstone); tin awnings upstairs on a quarter; a chimney on 55 in 100; a box
## oriel on a quarter of the stoop fronts; a silver roof on 60 in 100.
static func style(key: float, row_wall := "brick") -> Dictionary:
	var kind := row_wall
	var a := _r(key, 1)
	if a < 0.12:
		kind = "formstone"
	elif a < 0.18:
		kind = "formstone_tan"
	elif a < 0.25:
		kind = "painted"
	var t := _r(key, 2)
	var trim: Color = WHITE if t < 0.5 else (CREAM if t < 0.7 else (GREEN if t < 0.8 else (BROWN if t < 0.9 else RED)))
	var door: Color = DOORS.values()[int(_r(key, 3) * 6.0) % 6]
	var lintel: Variant = null
	if kind.begins_with("brick") and _r(key, 4) < 0.6:
		lintel = [WHITE, CREAM, STONE][int(_r(key, 5) * 3.0) % 3]
	var awning: Variant = null
	if _r(key, 6) < 0.25:
		awning = TIN[int(_r(key, 7) * 4.0) % 4]
	var o := _r(key, 11)
	var body: Variant = WHITE if o < 0.45 else (CREAM if o < 0.75 else (wall("painted") if o < 0.95 else wall("formstone")))
	return {"kind": kind, "wall": wall(kind), "trim": trim, "door": door, "lintel": lintel, "awning": awning,
		"chimney": _r(key, 8) < 0.55, "oriel": _r(key, 9) < 0.25, "oriel_body": body,
		"roof": SILVER if _r(key, 10) < 0.6 else TAR, "curtain": [Color(0.9, 0.7, 0.2), Color(0.85, 0.3, 0.3), Color(0.95, 0.93, 0.86), Color(0.4, 0.65, 0.4), Color(0.62, 0.5, 0.78)][int(_r(key, 12) * 5.0) % 5]}


## A row's cornice, as the old game deals them out (cornice_v2's recipes):
## porch rows 1 pressed metal 30, 4 corbelled brick 25, 0 restrained 15,
## 3 dentils 15, 5 pent 10, 2 parapet tablet 5; stoop rows 1 35, 4 20, 3 20, 0 20, 2 5.
static func profile_for(key: float, porch: bool) -> int:
	var r := Props.rnd(key * 5.31 + 0.77)
	var odds: Array = [[1, 0.3], [4, 0.25], [0, 0.15], [3, 0.15], [5, 0.1], [2, 0.05]] if porch else [[1, 0.35], [4, 0.2], [3, 0.2], [0, 0.2], [2, 0.05]]
	for pair: Array in odds:
		r -= float(pair[1])
		if r < 0.0:
			return pair[0]
	return 1


## Which of n windows glow: about `odds` of them, the same each time for the same key.
static func lit_pattern(key: float, n: int, odds := 0.35) -> String:
	var out := ""
	for i in n:
		var r := Props.rnd(key * 2.71 + float(i) * 0.87)
		out += ("t" if r > 1.0 - odds * 0.15 else "1") if r > 1.0 - odds else "0"
	return out


static func _lit(lit: String, i: int) -> Variant:
	if i >= lit.length():
		return null
	match lit[i]:
		"1":
			return LIT
		"t":
			return TV
	return null


# ------------------------------------------------------------- windows

## A double-hung sash window on a face, as the old game's kit draws it: frame,
## pane, meeting rail, sill, and a lintel over it on some brick fronts. `lit` is
## the colour the pane glows (null: a dark pane); `curtain` hangs either side
## of the pane (darker when it is not lit); `blind` pulls a blind half down instead.
static func sash(g: Node3D, s: float, y0: float, ww: float, wh: float, trim: Color, lit: Variant = null, curtain: Variant = null, lintel: Variant = null, blind := false) -> void:
	var half := ww * 0.5
	fb(g, s - half - 0.09, s + half + 0.09, y0 - 0.02, y0 + wh + 0.02, 0.0, 0.05, trim)
	fb(g, s - half - 0.15, s + half + 0.15, y0 - 0.13, y0 - 0.01, 0.0, 0.17, trim)
	if lintel != null:
		fb(g, s - half - 0.13, s + half + 0.13, y0 + wh + 0.04, y0 + wh + 0.24, 0.0, 0.08, lintel)
	Kit.pane(fb(g, s - half, s + half, y0 + 0.07, y0 + wh - 0.07, 0.05, 0.075, Kit.flat(lit, 1.1) if lit != null else PANE))
	var cloth: Variant = curtain
	if cloth != null and lit == null:
		cloth = (cloth as Color).darkened(0.6)
	if blind and lit != null:
		fb(g, s - half + 0.03, s + half - 0.03, y0 + wh * 0.52, y0 + wh - 0.085, 0.075, 0.082, Color(0.93, 0.9, 0.78))
		for k in int((wh * 0.48 - 0.1) / 0.09):
			fb(g, s - half + 0.035, s + half - 0.035, y0 + wh * 0.52 + 0.03 + k * 0.09, y0 + wh * 0.52 + 0.045 + k * 0.09, 0.082, 0.087, Color(0.82, 0.78, 0.66))
	elif cloth != null:
		if ww >= 0.8:
			for side: float in [-1.0, 1.0]:
				fb(g, s + side * (half - 0.17) - 0.13, s + side * (half - 0.17) + 0.13, y0 + 0.12, y0 + wh - 0.12, 0.075, 0.085, cloth)
		fb(g, s - half + 0.03, s + half - 0.03, y0 + wh - 0.3, y0 + wh - 0.1, 0.078, 0.09, (cloth as Color).darkened(0.15))
	fb(g, s - half + 0.015, s + half - 0.015, y0 + wh * 0.5 - 0.04, y0 + wh * 0.5 + 0.04, 0.055, 0.095, trim)


## The old game's "simple" window, for side and back walls: a trim frame, the
## glass, a sill; no lintel, no meeting rail.
static func simple_window(g: Node3D, s: float, y0: float, ww: float, wh: float, trim: Color, lit: Variant = null, curtain: Variant = null) -> void:
	var half := ww * 0.5
	fb(g, s - half - 0.07, s + half + 0.07, y0 - 0.02, y0 + wh + 0.07, 0.0, 0.04, trim)
	Kit.pane(fb(g, s - half, s + half, y0 + 0.05, y0 + wh, 0.04, 0.06, Kit.flat(lit, 1.1) if lit != null else PANE))
	fb(g, s - half - 0.1, s + half + 0.1, y0 - 0.1, y0 - 0.01, 0.0, 0.13, trim)
	if curtain != null and lit != null:
		for side: float in [-1.0, 1.0]:
			fb(g, s + side * (half - 0.14) - 0.11, s + side * (half - 0.14) + 0.11, y0 + 0.1, y0 + wh - 0.05, 0.06, 0.07, curtain)


## Boards nailed over a vacant's window or door: plywood, two battens.
static func boards(g: Node3D, s: float, y0: float, ww: float, wh: float) -> void:
	var half := ww * 0.5
	fb(g, s - half - 0.05, s + half + 0.05, y0 - 0.03, y0 + wh + 0.03, 0.1, 0.125, PLY)
	for y: float in [y0 + wh * 0.25, y0 + wh * 0.72]:
		fb(g, s - half - 0.08, s + half + 0.08, y - 0.04, y + 0.04, 0.125, 0.14, PLY.darkened(0.25))


## A Baltimore painted screen over the lower sash: a little red-roofed cottage
## by a pond under a blue sky, painted on the window screen.
static func painted_screen(g: Node3D, s: float, y0: float, ww: float, wh: float) -> void:
	var a := s - ww * 0.5 + 0.03
	var c := s + ww * 0.5 - 0.03
	var top := y0 + wh * 0.5 - 0.05
	var bottom := y0 + 0.08
	var h := top - bottom
	fb(g, a, c, bottom, top, 0.1, 0.11, Color(0.45, 0.7, 0.95))
	fb(g, a + 0.01, c - 0.01, bottom + 0.01, bottom + h * 0.38, 0.11, 0.116, Color(0.35, 0.68, 0.32))
	fb(g, a + 0.04, a + 0.3, bottom + h * 0.12, bottom + h * 0.24, 0.116, 0.12, Color(0.3, 0.5, 0.85))
	var hs := s + 0.12
	fb(g, hs - 0.17, hs + 0.17, bottom + h * 0.3, bottom + h * 0.62, 0.116, 0.122, Color(0.97, 0.95, 0.88))
	fb(g, hs - 0.21, hs + 0.21, bottom + h * 0.62, bottom + h * 0.76, 0.122, 0.128, Color(0.8, 0.18, 0.14))
	fb(g, hs - 0.05, hs + 0.05, bottom + h * 0.3, bottom + h * 0.5, 0.122, 0.126, Color(0.45, 0.28, 0.18))
	Kit.ball(g, 0.07, Vector3(c - 0.12, bottom + h * 0.8, 0.12), Color(1.0, 0.85, 0.3), 6)
	Kit.ball(g, 0.09, Vector3(a + 0.14, bottom + h * 0.55, 0.12), Color(0.2, 0.5, 0.25), 6)


## A tin awning over a window whose head is at y: a ribbed sheet sloping out
## from the wall, a valance along its front edge.
static func tin_awning(g: Node3D, s: float, y: float, ww: float, colour: Color) -> void:
	var a := Kit.group(g, Vector3(s, y + 0.2, 0.3), Vector3(28, 0, 0))
	var span := ww + 0.34
	Kit.box(a, Vector3(span, 0.035, 0.66), Vector3.ZERO, colour)
	var n := int(span / 0.22)
	for k in n:
		Kit.box(a, Vector3(0.05, 0.05, 0.64), Vector3(-span * 0.5 + (k + 0.5) * span / n, 0.012, 0.0), colour.lightened(0.16))
	fb(g, s - span * 0.5, s + span * 0.5, y - 0.07, y + 0.06, 0.555, 0.585, colour.darkened(0.12))


## A box oriel upstairs (the old game's facade v2, on a quarter of the stoop
## fronts): a painted box `ww` wide standing `dd` out, two sashes in its face,
## a sill band, a little cornice and a tar cap, brackets under it.
static func oriel(g: Node3D, s: float, base: float, top: float, ww: float, dd: float, body: Variant, trim: Color, lit: Variant, curtain: Variant) -> void:
	var half := ww * 0.5
	fb(g, s - half, s + half, base, top, -0.02, dd, body)
	var f := Kit.group(g, Vector3(0, 0, dd))
	var sw := (ww - 0.62) * 0.5
	for side: float in [-1.0, 1.0]:
		sash(f, s + side * (sw * 0.5 + 0.1), base + 0.32, sw, top - base - 0.6, trim, lit, curtain)
	fb(g, s - half - 0.04, s + half + 0.04, base - 0.12, base, -0.02, dd + 0.05, trim)
	fb(g, s - half - 0.06, s + half + 0.06, top, top + 0.14, -0.02, dd + 0.1, trim)
	fb(g, s - half - 0.08, s + half + 0.08, top + 0.14, top + 0.19, -0.02, dd + 0.13, TAR)
	for x: float in [s - half + 0.16, s + half - 0.16]:
		fb(g, x - 0.07, x + 0.07, base - 0.5, base - 0.12, 0.0, dd - 0.08, trim)


# ---------------------------------------------------------------- cornices

## The cornice along a front w wide whose top is at `height`, in one of the old
## game's profiles: 0 restrained (a plain band, small brackets), 1 pressed
## metal (Rose Hill's: a deep band on brackets), 2 parapet tablet (a coping and
## a raised panel), 3 dentils, 4 corbelled brick (a corbel table in the wall's
## own brick under a metal flashing), 5 pent (a short false-mansard slope).
## Brackets skip the bay at skip_s (skip_w wide).
static func cornice(g: Node3D, w: float, height: float, trim: Color, profile := 1, wall_look: Variant = null, skip_s := -99.0, skip_w := 0.0, roofing: Variant = TAR) -> void:
	match profile:
		0:
			fb(g, 0.0, w, height - 0.42, height - 0.14, 0.0, 0.14, trim)
			fb(g, 0.0, w, height - 0.14, height - 0.03, 0.0, 0.24, trim)
			fb(g, 0.0, w, height - 0.03, height + 0.02, 0.0, 0.2, TAR)
			_brackets(g, w, height - 0.62, height - 0.42, 0.18, trim, skip_s, skip_w, 2.0)
		2:
			fb(g, 0.0, w, height - 1.02, height - 0.92, 0.0, 0.07, trim)
			fb(g, w * 0.3, w * 0.7, height - 0.78, height - 0.28, 0.0, 0.05, trim)
			fb(g, w * 0.3 + 0.08, w * 0.7 - 0.08, height - 0.7, height - 0.36, 0.05, 0.07, trim.darkened(0.1))
			fb(g, -0.02, w + 0.02, height - 0.12, height + 0.02, -0.3, 0.06, STONE)
		3:
			fb(g, 0.0, w, height - 0.6, height - 0.32, 0.0, 0.08, trim)
			var n := int((w - 0.1) / 0.2)
			for i in n:
				var s := 0.1 + (i + 0.5) * (w - 0.2) / n
				fb(g, s - 0.05, s + 0.05, height - 0.32, height - 0.2, 0.0, 0.12, trim)
			fb(g, 0.0, w, height - 0.2, height - 0.04, 0.0, 0.3, trim)
			fb(g, 0.0, w, height - 0.04, height + 0.02, 0.0, 0.25, TAR)
		4:
			var look: Variant = wall_look if wall_look != null else trim
			fb(g, 0.0, w, height - 0.5, height - 0.36, 0.0, 0.07, look)
			fb(g, 0.0, w, height - 0.36, height - 0.2, 0.0, 0.13, look)
			var n := maxi(2, int(w / 0.36))
			for i in n:
				var s := (i + 0.5) * w / n
				fb(g, s - 0.09, s + 0.09, height - 0.74, height - 0.5, 0.0, 0.07, look)
			fb(g, -0.01, w + 0.01, height - 0.2, height + 0.02, -0.25, 0.17, SILVER)
		5:
			var slope := Kit.group(g, Vector3(w * 0.5, height - 0.45, 0.31), Vector3(56, 0, 0))
			Kit.box(slope, Vector3(w, 0.06, 0.98), Vector3.ZERO, roofing)
			var n := maxi(2, int(w / 0.5))
			for i in n:
				Kit.box(slope, Vector3(0.04, 0.075, 0.96), Vector3(-w * 0.5 + (i + 0.5) * w / n, 0.01, 0.0), (roofing as Color).lightened(0.12) if roofing is Color else STONE)
			fb(g, 0.0, w, height - 0.96, height - 0.86, 0.0, 0.62, trim)
			fb(g, 0.0, w, height - 0.06, height + 0.02, -0.2, 0.1, TAR)
		_:
			fb(g, 0.0, w, height - 0.52, height - 0.2, 0.0, 0.2, trim)
			fb(g, 0.0, w, height - 0.2, height - 0.04, 0.0, 0.34, trim)
			fb(g, 0.0, w, height - 0.04, height + 0.02, 0.0, 0.28, TAR)
			_brackets(g, w, height - 0.88, height - 0.52, 0.27, trim, skip_s, skip_w, 1.6)


static func _brackets(g: Node3D, w: float, y0: float, y1: float, out: float, trim: Color, skip_s: float, skip_w: float, every: float) -> void:
	var n := maxi(2, int(w / every) + 1)
	for i in n:
		var s := 0.22 + i * (w - 0.44) / (n - 1)
		if absf(s - skip_s) < skip_w * 0.5 + 0.2:
			continue
		fb(g, s - 0.08, s + 0.08, y0, y1, 0.0, out, trim)


# ------------------------------------------------------------ the porch row

## One of Rose Hill's porch-front rowhouses, its front on v = d from u0 to
## u0 + w (see porch_front).
static func porch_house(p: Node3D, b: int, u0: float, d: float, w: float, h: Dictionary) -> Node3D:
	return porch_front(face(p, b, u0, d), w, h)


## A porch-front rowhouse on face g, w wide: two storeys and a flat roof; an
## open porch the width of the house on a solid grey deck, three posts, a
## railing with its opening at the steps, risers down to the pavement; the door
## with its transom (the number in gold) and two windows; upstairs the
## three-sided sash bay standing on the porch roof on the side away from the
## door (Rose Hill's mark) and one sash over the door; a cornice; a chimney on
## some. Mirror neighbours in pairs, so doors and steps come two together.
##
## h: "wall" (a look), "trim", "door" (colours), "door_left", "no" (the house
## number), "bay" ("white", "cream", "grey", or "none": two sashes instead),
## "lintel" (a colour or null), "height" (to the top of the cornice),
## "chimney", "porch" (false: a marble stoop and no porch), "profile" (the
## cornice, see `cornice`; 1 by default), "roof" (its colour), "deep", "infill"
## (a look: solid knee walls on the porch instead of balusters); the porch's
## sizes "f0" (the deck), "ceil", "proof", "pd" (default Rose Hill's); and the
## pop-up's own: "lit" (five letters, "1" lit, "t" the blue of a television:
## the window nearer the door, the other one, the bay, the sash over the door,
## the transom), "curtain" (a colour), "blinds", "porch_light", "screens",
## "pots", "chairs", "fern".
static func porch_front(g: Node3D, w: float, h: Dictionary) -> Node3D:
	var wall_look: Variant = h["wall"]
	var trim: Color = h.get("trim", WHITE)
	var height: float = h.get("height", 8.0)
	var deep: float = h.get("deep", 9.0)
	var porch: bool = h.get("porch", true)
	var f0: float = h.get("f0", F0)
	var proof: float = h.get("proof", PROOF)
	var lit: String = h.get("lit", "00000")
	var curtain: Variant = h.get("curtain", null)
	var lintel: Variant = h.get("lintel", null)
	var door_left: bool = h.get("door_left", true)
	var door_s := 0.9 if door_left else w - 0.9
	var into := 1.0 if door_left else -1.0          # from the door towards the middle of the house
	var k := w / 6.47
	var wins: Array = []
	for c: float in [3.23 * k, 1.08 * k]:            # the window nearer the door first
		var s := w - c if door_left else c
		if absf(s - door_s) > 1.3:
			wins.append(s)

	# The house itself, its roof, the base course, a chimney.
	fb(g, 0.0, w, 0.0, height, -deep, 0.0, wall_look)
	fb(g, 0.0, w, height, height + 0.04, -deep, -0.36, h.get("roof", TAR))
	if not porch and f0 > 0.1:
		fb(g, 0.0, w, 0.0, f0 - 0.04, 0.0, 0.04, BASE)
	if h.get("chimney", false):
		var cs := w - 0.6 if door_left else 0.6
		var ct := 6.4 if deep >= 9.0 else deep * 0.7
		fb(g, cs - 0.35, cs + 0.35, height, height + 1.3, -ct, -ct + 0.5, wall_look)
		fb(g, cs - 0.4, cs + 0.4, height + 1.3, height + 1.38, -ct - 0.05, -ct + 0.55, CONCRETE)

	# The ground floor: the windows, the door.
	for i in wins.size():
		var s: float = wins[i]
		sash(g, s, f0 + 0.7, 0.95, 1.7, trim, _lit(lit, i), curtain, lintel, h.get("blinds", false))
		if h.get("screens", false):
			painted_screen(g, s, f0 + 0.7, 0.95, 1.7)
	_door(g, door_s, h)

	# The porch, or a marble stoop.
	if porch:
		_porch(g, w, door_s, into, h)
	else:
		_stoop(g, door_s, into, h)

	# Upstairs: the bay (or two sashes), the sash over the door, the cornice.
	var kind: String = h.get("bay", "white")
	var base := proof + 0.05 if porch else f0 + 3.6
	var top := height - 0.65 - 0.205
	var sh := minf(1.72, top - 0.22 - base - 0.5)
	var sz := top - 0.22 - sh
	var bay_s := w * (0.66 if door_left else 0.34)
	var bay_w := 0.0
	if kind == "none":
		for s: float in wins:
			sash(g, s, top - 0.22 - 1.65, 0.95, 1.65, trim, _lit(lit, 2), curtain, lintel)
		bay_s = -99.0
	else:
		var bay: Array = BAYS[kind]
		bay_w = bay[0]
		_bay(g, bay_s, bay, kind, base, top, sz, sh, _lit(lit, 2), curtain, porch)
	sash(g, door_s, top - 0.22 - 1.65, 0.95, 1.65, trim, _lit(lit, 3), curtain, lintel if kind == "none" else null)
	cornice(g, w, height, trim, h.get("profile", 1), wall_look, bay_s, bay_w, h.get("pent", TAR))
	return g


static func _door(g: Node3D, s: float, h: Dictionary) -> void:
	var f0: float = h.get("f0", F0)
	var trim: Color = h.get("trim", WHITE)
	var leaf: Color = h.get("door", DOORS["red"])
	fb(g, s - 0.62, s + 0.62, f0, f0 + 2.78, 0.0, 0.05, trim)
	fb(g, s - 0.48, s + 0.48, f0, f0 + 2.16, 0.05, 0.085, leaf)
	for y: float in [f0 + 0.25, f0 + 1.2]:
		fb(g, s - 0.36, s + 0.36, y, y + 0.75, 0.085, 0.1, leaf.lightened(0.14))
	Kit.pane(fb(g, s - 0.48, s + 0.48, f0 + 2.26, f0 + 2.66, 0.05, 0.075, Kit.flat(LIT, 0.85) if _lit(h.get("lit", ""), 4) != null else PANE))
	if h.get("no", "") != "":
		Props.words(g, h.get("no", ""), Vector3(s, f0 + 2.46, 0.082), 0.2, GOLD)
	var knob := s + (0.32 if h.get("door_left", true) else -0.32)
	fb(g, knob - 0.04, knob + 0.04, f0 + 1.0, f0 + 1.08, 0.1, 0.14, GOLD)


static func _porch(g: Node3D, w: float, door_s: float, into: float, h: Dictionary) -> void:
	var trim: Color = h.get("trim", WHITE)
	var f0: float = h.get("f0", F0)
	var ceil_y: float = h.get("ceil", CEIL)
	var proof: float = h.get("proof", PROOF)
	var pd: float = h.get("pd", PD)
	var infill: Variant = h.get("infill", null)
	var gap := [door_s - 0.66, door_s + 0.66]
	var posts := [0.16, w * 0.5, w - 0.16]
	# The deck: one solid grey box, the width of the house.
	if f0 > 0.0:
		fb(g, 0.0, w, 0.0, f0, 0.0, pd, PORCH)
	# Posts, the flat roof on them, a fascia in the trim colour.
	for s: float in posts:
		fb(g, s - 0.1, s + 0.1, f0, ceil_y, pd - 0.33, pd - 0.13, trim)
	fb(g, 0.0, w, ceil_y, proof, 0.0, pd + 0.18, PORCH_ROOF)
	fb(g, 0.006, w - 0.006, ceil_y - 0.24, ceil_y + 0.06, pd + 0.06, pd + 0.2, trim)
	# The railing (or solid knee walls), its opening at the steps with a newel either side.
	for i in 2:
		for span: Array in _cut([posts[i] + 0.1, posts[i + 1] - 0.1], gap):
			var a: float = span[0]
			var c: float = span[1]
			if absf(c - gap[0]) < 0.001:
				fb(g, c - 0.13, c, f0, f0 + 1.0, pd - 0.31, pd - 0.15, trim)
				c -= 0.13
			if absf(a - gap[1]) < 0.001:
				fb(g, a, a + 0.13, f0, f0 + 1.0, pd - 0.31, pd - 0.15, trim)
				a += 0.13
			fb(g, a, c, f0 + 0.82, f0 + 0.93, pd - 0.28, pd - 0.18, trim)
			if infill != null:
				fb(g, a, c, f0, f0 + 0.82, pd - 0.27, pd - 0.19, infill)
				continue
			fb(g, a, c, f0 + 0.1, f0 + 0.18, pd - 0.27, pd - 0.19, trim)
			var n := maxi(int((c - a) / 0.3), 1)
			for j in n:
				var x: float = a + (j + 0.5) * (c - a) / n
				fb(g, x - 0.035, x + 0.035, f0 + 0.18, f0 + 0.82, pd - 0.26, pd - 0.2, trim)
	for s: float in [0.08, w - 0.08]:
		fb(g, s - 0.05, s + 0.05, f0 + 0.82, f0 + 0.93, 0.0, pd - 0.33, trim)
	# The steps down, the same grey: as many as the deck needs.
	var steps := roundi(f0 / RISE) - 1
	if steps > 0:
		var rise := f0 / (steps + 1)
		for k in steps:
			fb(g, door_s - 0.625, door_s + 0.625, 0.0, f0 - rise * (k + 1), pd + 0.3 * k, pd + 0.3 * (k + 1), PORCH)
	# The porch light, under the roof's front edge over the steps.
	var on: bool = h.get("porch_light", false)
	fb(g, door_s - 0.09, door_s + 0.09, ceil_y - 0.05, ceil_y, pd - 0.45, pd - 0.27, IRON)
	Kit.ball(g, 0.1, Vector3(door_s, ceil_y - 0.13, pd - 0.36), Kit.flat(Color(1.0, 0.86, 0.55), 1.8) if on else Color(0.62, 0.6, 0.55), 8)
	if on:
		Kit.omni(g, Vector3(door_s, ceil_y - 0.35, pd + 0.2), Color(1.0, 0.84, 0.58), 2.4, 5.5)
	# The pop-up's own: things on the porch.
	if h.get("chairs", false):
		var cs := w * 0.5 + into * 1.2
		porch_chair(g, cs - 0.4, 0.8, Color(0.4, 0.75, 0.7), 12.0, f0)
		porch_chair(g, cs + 0.4, 0.8, Color(0.95, 0.55, 0.5), -8.0, f0)
	if h.get("fern", false):
		for s: float in [w * 0.5 - 0.6, w * 0.5 + 0.6]:
			Kit.cyl(g, 0.006, 0.45, Vector3(s, ceil_y - 0.22, pd - 0.45), IRON, Vector3.ZERO, 4)
			Kit.cyl(g, 0.16, 0.14, Vector3(s, ceil_y - 0.5, pd - 0.45), Color(0.6, 0.35, 0.22), Vector3.ZERO, 8, 0.12)
			Kit.ball(g, 0.26, Vector3(s, ceil_y - 0.5, pd - 0.45), Color(0.28, 0.58, 0.26), 7)
	if h.get("pots", false):
		for j in 3:
			var ps := door_s + into * (0.95 + j * 0.42)
			Kit.cyl(g, 0.13, 0.24, Vector3(ps, f0 + 0.12, pd - 0.55), Color(0.72, 0.38, 0.24), Vector3.ZERO, 8, 0.1)
			Kit.ball(g, 0.15, Vector3(ps, f0 + 0.33, pd - 0.55), [Color(0.9, 0.25, 0.35), Color(0.95, 0.8, 0.2), Color(0.85, 0.4, 0.75)][j], 6)


## Pieces of [a, b] left when `hole` (another [a, b]) is cut out of it.
static func _cut(span: Array, hole: Array) -> Array:
	var out: Array = []
	if hole[1] <= span[0] or hole[0] >= span[1]:
		return [span]
	if hole[0] > span[0] + 0.05:
		out.append([span[0], hole[0]])
	if hole[1] < span[1] - 0.05:
		out.append([hole[1], span[1]])
	return out


static func _stoop(g: Node3D, door_s: float, into: float, h: Dictionary) -> void:
	# A marble stoop, white as scrubbed: a landing at the door and risers down, no rail.
	var f0: float = h.get("f0", F0)
	var steps := roundi(f0 / RISE) - 1
	var rise := f0 / (steps + 1)
	fb(g, door_s - 0.7, door_s + 0.7, 0.0, f0, -0.01, 0.45, MARBLE)
	for k in steps:
		fb(g, door_s - 0.7, door_s + 0.7, 0.0, f0 - rise * (k + 1), 0.45 + 0.3 * k, 0.45 + 0.3 * (k + 1), MARBLE)
	_door_lamp(g, door_s + into * 0.85, f0, h.get("porch_light", false))


## A lamp on the wall beside a door.
static func _door_lamp(g: Node3D, s: float, f0: float, on: bool) -> void:
	fb(g, s - 0.08, s + 0.08, f0 + 2.0, f0 + 2.32, 0.0, 0.04, IRON)
	Kit.box(g, Vector3(0.14, 0.24, 0.14), Vector3(s, f0 + 2.1, 0.12), Kit.flat(Color(1.0, 0.86, 0.55), 1.6) if on else Color(0.5, 0.48, 0.42))
	if on:
		Kit.omni(g, Vector3(s, f0 + 2.0, 0.8), Color(1.0, 0.84, 0.58), 2.0, 4.8)


## Rose Hill's canted sash bay ("white", "cream" or "grey") centred at `at` on
## face g, standing from `base` (the porch roof's top) to `top`.
static func canted_bay(g: Node3D, at: float, kind: String, base: float, top: float, lit: Variant = null, curtain: Variant = null, porch := true) -> void:
	var sh := minf(1.72, top - 0.22 - base - 0.5)
	_bay(g, at, BAYS[kind], kind, base, top, top - 0.22 - sh, sh, lit, curtain, porch)


## The three-sided sash bay upstairs: a sash in each face, a clapboard apron
## below them, a sill band and two cornice bands wrapping round, a tar cap.
static func _bay(g: Node3D, at: float, bay: Array, kind: String, base: float, top: float, sz: float, sh: float, lit: Variant, curtain: Variant, porch: bool) -> void:
	var bw: float = bay[0]
	var bd: float = bay[1]
	var hf: float = bw * float(bay[2])
	var body: Variant = WHITE if kind == "white" else (CREAM if kind == "cream" else Kit.tex("painted_block", 0.7, Color(0.6, 0.59, 0.55), true, Color(0.8, 0.8, 0.84)))
	var trim := CREAM.lightened(0.15) if kind == "cream" else WHITE
	var clap := Color(0.66, 0.64, 0.6)
	var outline := [Vector2(at - bw * 0.5, 0.0), Vector2(at - hf, bd), Vector2(at + hf, bd), Vector2(at + bw * 0.5, 0.0)]
	for i in 3:
		var f := sub_face(g, outline[i], outline[i + 1])
		var l: float = (outline[i + 1] - outline[i]).length()
		var front := i == 1
		fb(f, 0.0, l, base, top, -bd if front else -0.45, 0.0, body)
		sash(f, l * 0.5, sz, l - 0.24, sh, trim, lit, curtain)
		fb(f, -0.03, l + 0.03, base, base + 0.11, -0.025, 0.09, trim)
		fb(f, -0.045, l + 0.045, top - 0.02, top + 0.1, -0.03, 0.12, trim)
		fb(f, -0.065, l + 0.065, top + 0.1, top + 0.17, -0.04, 0.17, trim)
		fb(f, -0.065 if front else 0.0, l + 0.065 if front else l, top + 0.17, top + 0.205, -bd if front else -0.45, 0.17, TAR)
		var y := base + 0.2
		while y < sz - 0.17:
			fb(f, 0.02, l - 0.02, y, y + 0.02, 0.0, 0.012, clap)
			y += 0.18
	if not porch:
		# Brackets under a bay that does not stand on a porch roof.
		for s: float in [at - hf + 0.12, at + hf - 0.12]:
			fb(g, s - 0.07, s + 0.07, base - 0.5, base, 0.0, bd - 0.08, trim)
			fb(g, s - 0.07, s + 0.07, base - 0.62, base - 0.5, 0.0, 0.18, trim)


## A metal shell-back porch chair, the kind every Baltimore porch had.
static func porch_chair(g: Node3D, s: float, t: float, paint: Color, turn := 8.0, f0 := F0) -> void:
	var c := Kit.group(g, Vector3(s, f0, t), Vector3(0, turn, 0))
	Kit.box(c, Vector3(0.48, 0.05, 0.42), Vector3(0, 0.4, 0.02), paint)
	Kit.box(c, Vector3(0.5, 0.45, 0.05), Vector3(0, 0.68, -0.2), paint, Vector3(-12, 0, 0))
	var shell := Kit.ball(c, 0.25, Vector3(0, 0.88, -0.22), paint, 8)
	shell.scale = Vector3(1.0, 0.45, 0.2)
	for x: float in [-0.21, 0.21]:
		Kit.box(c, Vector3(0.035, 0.4, 0.035), Vector3(x, 0.2, 0.18), IRON)
		Kit.box(c, Vector3(0.035, 0.035, 0.42), Vector3(x, 0.02, 0.0), IRON)
		Kit.box(c, Vector3(0.04, 0.04, 0.34), Vector3(x + signf(x) * 0.02, 0.56, 0.02), paint)


# ------------------------------------------------------------ the stoop row

## Marble steps up to a door at s on a face, the threshold f0 up: a landing
## (0.45 deep on a full stoop) and treads 0.28 deep, as many risers as f0
## needs at about 0.18. Returns how far it reaches out from the wall.
static func stoop(g: Node3D, s: float, f0: float, half := 0.7, look: Variant = MARBLE) -> float:
	var n := maxi(1, roundi(f0 / 0.18))
	var rise := f0 / n
	var land := 0.45 if n >= 3 else 0.4
	fb(g, s - half, s + half, 0.0, f0, -0.01, land, look)
	for k in range(1, n):
		var c: Variant = (look as Color).darkened(0.03 * k) if look is Color else look
		fb(g, s - half, s + half, 0.0, f0 - rise * k, land + 0.28 * (k - 1), land + 0.28 * k, c)
	return land + 0.28 * (n - 1)


## A stoop-front rowhouse on face g, w wide (the old game's "row" houses):
## the wall, a flat roof, a base course; the door 0.9 from its side, in a
## frame under a transom, up its marble stoop; the old game's window bays
## (one per 1.7 m of front, two to four), the ground-floor ones clear of the
## door; sashes with lintels on some; a box oriel over the ground window on
## some, tin awnings on some; the row's cornice; a chimney on some.
##
## o: "wall" (a look), "trim", "door" (colours), "door_left", "f0" (the
## threshold: 0.7 in the old game), "height" (the top of the cornice), "floors",
## "deep" (how far back the box runs), "lintel", "awning" (a colour), "oriel"
## (true), "oriel_body", "profile" (see `cornice`), "roof", "chimney", "lit"
## (one letter per window, ground floor first, left to right: "1" lit, "t" a
## television), "transom" (lit), "curtain", "blinds", "boarded" (a
## vacant: plywood over the door and windows), "porch_light", "no" (a number on
## the transom), "pent" (the roofing on a pent cornice).
## Returns {"door": where along the door is, "stoop": how far its steps reach}.
static func stoop_front(g: Node3D, w: float, o: Dictionary) -> Dictionary:
	var wall_look: Variant = o["wall"]
	var trim: Color = o.get("trim", WHITE)
	var f0: float = o.get("f0", F0)
	var height: float = o.get("height", 8.0)
	var floors: int = o.get("floors", 2)
	var deep: float = o.get("deep", 9.0)
	var door_left: bool = o.get("door_left", true)
	var lit: String = o.get("lit", "")
	var curtain: Variant = o.get("curtain", null)
	var lintel: Variant = o.get("lintel", null)
	var boarded: bool = o.get("boarded", false)
	var ds := 0.9 if door_left else w - 0.9
	var into := 1.0 if door_left else -1.0

	# The house, its roof, the base course, a chimney.
	fb(g, 0.0, w, 0.0, height, -deep, 0.0, wall_look)
	fb(g, 0.0, w, height, height + 0.04, -deep, -0.36, o.get("roof", TAR))
	if f0 > 0.1:
		fb(g, 0.0, w, 0.0, f0 - 0.04, 0.0, 0.04, BASE)
	if o.get("chimney", false):
		var cs := w - 0.6 if door_left else 0.6
		var ct := minf(6.4, deep * 0.7)
		fb(g, cs - 0.35, cs + 0.35, height, height + 1.3, -ct, -ct + 0.5, wall_look)
		fb(g, cs - 0.41, cs + 0.41, height + 1.3, height + 1.44, -ct - 0.06, -ct + 0.56, STONE)

	# The window bays, as the old game sets them out.
	var n := clampi(int(w / 1.7), 1, 4)
	var cols: Array = []
	for i in n:
		cols.append((i + 0.5) * w / n)
	var storey := (height - 0.9 - f0) / floors
	var idx := 0
	# The ground floor: the windows clear of the door, the door, the stoop.
	var low: Array = []
	for c: float in cols:
		if absf(c - ds) >= 1.215:
			low.append(c)
	for c: float in low:
		if boarded:
			sash(g, c, f0 + 0.7, 0.95, 1.7, trim, null, null, lintel)
			boards(g, c, f0 + 0.7, 0.95, 1.7)
		else:
			sash(g, c, f0 + 0.7, 0.95, 1.7, trim, _lit(lit, idx), curtain, lintel, o.get("blinds", false))
		idx += 1
	var d := {"f0": f0, "trim": trim, "door": o.get("door", DOORS["red"]), "door_left": door_left, "no": o.get("no", ""), "lit": "00001" if o.get("transom", false) else ""}
	_door(g, ds, d)
	if boarded:
		boards(g, ds, f0, 0.96, 2.2)
	var reach := 0.0
	if f0 > 0.05:
		reach = stoop(g, ds, f0)
	if not boarded:
		_door_lamp(g, ds + into * 0.85, f0, o.get("porch_light", false))

	# Upstairs: sashes (an oriel over the far ones on some), awnings on some.
	var oriel_at := -99.0
	if o.get("oriel", false) and floors >= 2 and not boarded:
		var far: float = cols[n - 1] if door_left else cols[0]
		if absf(far - ds) >= 1.215:
			oriel_at = far
	for f in range(1, floors):
		var y0 := f0 + f * storey + 0.6
		var wh := minf(1.65, storey - 0.9)
		for c: float in cols:
			if f == 1 and absf(c - oriel_at) < 0.01:
				var ow := clampf(w / n + 0.35, 1.8, 2.1)
				oriel(g, clampf(c, ow * 0.5 + 0.12, w - ow * 0.5 - 0.12), y0 - 0.45, y0 + wh + 0.25, ow, 0.52, o.get("oriel_body", WHITE), trim, _lit(lit, idx), curtain)
				idx += 1
				continue
			if boarded:
				sash(g, c, y0, 0.95, wh, trim, null, null, lintel)
				boards(g, c, y0, 0.95, wh)
			else:
				sash(g, c, y0, 0.95, wh, trim, _lit(lit, idx), curtain, lintel, o.get("blinds", false))
				if f == 1 and o.get("awning", null) != null:
					tin_awning(g, c, y0 + wh + (0.26 if lintel != null else 0.04), 0.95, o["awning"])
			idx += 1
	cornice(g, w, height, trim, o.get("profile", 1), wall_look, -99.0, 0.0, o.get("pent", TAR))
	return {"door": ds, "stoop": reach}


## The windows down the open end of a row, on face g's left end (side -1) or
## right end (+1): the old game's simple windows every 2.6 m on each floor, from
## 1.6 m behind the front to near the back, some lit.
static func end_windows(g: Node3D, w: float, deep: float, side: int, f0: float, height: float, trim: Color, key: float, floors := 2) -> Node3D:
	var f: Node3D
	if side < 0:
		f = sub_face(g, Vector2(0.0, -deep), Vector2(0.0, 0.0))      # s from the back to the front
	else:
		f = sub_face(g, Vector2(w, 0.0), Vector2(w, -deep))          # s from the front to the back
	var storey := (height - 0.9 - f0) / floors
	var at := 1.6
	var i := 0
	while at < deep - 0.9:
		var s := deep - at if side < 0 else at
		for fl in floors:
			var y0 := f0 + fl * storey + (0.75 if fl == 0 else 0.6)
			var lit: Variant = LIT if Props.rnd(key + i * 1.7 + fl * 0.9) > 0.7 else null
			simple_window(f, s, y0, 0.95, minf(1.55, storey - 0.95), trim, lit, Color(0.85, 0.75, 0.55))
		at += 2.6
		i += 1
	return f


## A plain stoop-front rowhouse (Old York Road's), on a face: a door and its
## marble steps, the windows, a cornice. lit: one letter per window ("1" lit),
## ground floor first, left to right.
static func plain_house(g: Node3D, w: float, height: float, wall_look: Variant, trim: Color, door: Color, lit := "", floors := 2, door_left := true) -> void:
	fb(g, 0.0, w, 0.0, height, -9.0, 0.0, wall_look)
	fb(g, 0.0, w, height, height + 0.04, -9.0, -0.36, TAR)
	fb(g, 0.0, w, 0.0, F0 - 0.04, 0.0, 0.04, BASE)
	var ds := 0.9 if door_left else w - 0.9
	fb(g, ds - 0.62, ds + 0.62, F0, F0 + 2.78, 0.0, 0.05, trim)
	fb(g, ds - 0.48, ds + 0.48, F0, F0 + 2.16, 0.05, 0.085, door)
	Kit.pane(fb(g, ds - 0.48, ds + 0.48, F0 + 2.26, F0 + 2.66, 0.05, 0.075, Kit.flat(LIT, 0.8) if lit.length() > 0 and lit[0] == "1" else PANE))
	fb(g, ds - 0.7, ds + 0.7, 0.0, F0, -0.01, 0.45, MARBLE)
	for k in 3:
		fb(g, ds - 0.7, ds + 0.7, 0.0, F0 - RISE * (k + 1), 0.45 + 0.3 * k, 0.45 + 0.3 * (k + 1), MARBLE)
	var cols: Array = []
	var n := maxi(1, int((w - 0.4) / 1.5))
	for i in n:
		cols.append(0.3 + (i + 0.5) * (w - 0.6) / n)
	var idx := 1
	var storey := (height - 0.9 - F0) / floors
	for c: float in cols:
		if absf(c - ds) > 1.25:
			sash(g, c, F0 + 0.7, 0.95, 1.7, trim, LIT if lit.length() > idx and lit[idx] == "1" else null, Color(0.85, 0.3, 0.25))
			idx += 1
	for f in range(1, floors):
		for c: float in cols:
			sash(g, c, F0 + f * storey + 0.6, 0.95, minf(1.65, storey - 0.9), trim, LIT if lit.length() > idx and lit[idx] == "1" else null, Color(0.9, 0.85, 0.7))
			idx += 1
	fb(g, 0.0, w, height - 0.52, height - 0.2, 0.0, 0.2, trim)
	fb(g, 0.0, w, height - 0.2, height - 0.04, 0.0, 0.34, trim)
	fb(g, 0.0, w, height - 0.04, height + 0.02, 0.0, 0.28, TAR)
