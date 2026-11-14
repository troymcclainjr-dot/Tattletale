extends RefCounted
## Pieces for Rose Hill Terrace (plans/street.gd), the short copy of the old
## Pen Lucy's side street: its porch-front rowhouses with the projecting sash
## bays upstairs, a plain stoop-front rowhouse, the cobra-head street lamps and
## the wooden utility poles, the neighbourhood's parked cars, the corner sign
## post with its stop sign, a mailbox, a bus stop, litter.
##
## A house front is built on a FACE: a group standing at the front's left end
## (as seen from in front of it), its x running along the front to the right,
## its y up and its z pointing out of the wall. `fb` puts a box on a face from
## its ranges (s along, y up, t out), so a house can be stood facing any way.
##
##   const Street := preload("res://scripts/props_street.gd")
##   Street.porch_house(p, band, 6.33, 10.0, 6.53, {"no": "518", "wall": brick, ...})
##   Street.parked_car(p, band, 13.5, 17.7, 270.0, "compact", Street.PAINT[1])
##
## Sizes and colours are the old game's (blender/city/kits.py, process.py and
## the measured street), the colours a touch brighter for the pop-up's night.

const Props := preload("res://scripts/props.gd")

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
const TAR := Color(0.27, 0.27, 0.3)             # (62, 62, 68)
const BASE := Color(0.6, 0.59, 0.55)            # the grey base course
const MARBLE := Color(0.94, 0.93, 0.89)         # (238, 234, 224)
const CONCRETE := Color(0.72, 0.71, 0.68)
const PANE := Color(0.11, 0.14, 0.2)            # glass (26, 34, 48)
const IRON := Color(0.12, 0.12, 0.14)
const LIT := Color(1.0, 0.8, 0.48)
const TV := Color(0.55, 0.72, 1.0)
const GOLD := Color(0.95, 0.78, 0.3)
const LAMP := Color(1.0, 0.88, 0.65)            # the street lamps (255, 224, 166)
## The parked cars' paints, in the old game's order.
const PAINT := [Color(0.36, 0.44, 0.52), Color(0.82, 0.78, 0.7), Color(0.36, 0.45, 0.39), Color(0.58, 0.33, 0.31), Color(0.53, 0.58, 0.62), Color(0.3, 0.33, 0.36)]

const F0 := 0.7              # the ground floor (and the porch deck) above the pavement
const CEIL := 3.8            # the porch ceiling
const PROOF := 4.0           # the top of the porch roof: 3.3 above the deck
const PD := 2.0              # how deep the porch is
const RISE := 0.175          # four risers from the deck to the paved strip

## Rose Hill's three upper bays: width, how far it stands out, half the front's share of the width.
const BAYS := {"white": [2.25, 0.64, 0.29], "cream": [2.05, 0.52, 0.32], "grey": [2.35, 0.72, 0.27]}


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
	fb(g, s - half, s + half, y0 + 0.07, y0 + wh - 0.07, 0.05, 0.075, Kit.flat(lit, 1.1) if lit != null else PANE)
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


# ------------------------------------------------------------------- houses

## One of Rose Hill's porch-front rowhouses, its front on v = d from u0 to
## u0 + w: two storeys and a flat tar roof; an open porch the width of the
## house on a solid grey deck 0.7 high, three posts, a railing with its opening
## at the steps, four risers down to the paved strip; the door with its transom
## (the number in gold) and two windows; upstairs the three-sided sash bay
## standing on the porch roof on the side away from the door (the street's own
## mark) and one sash over the door; a cornice band on brackets; a chimney on
## some. The houses are mirrored in pairs, so doors and steps come two together.
##
## h: "no" (the house number), "wall" (a look), "trim", "door" (colours),
## "door_left", "bay" ("white", "cream", "grey"), "lintel" (a colour or null),
## "height" (to the top of the cornice), "chimney", "porch" (false: a marble
## stoop and no porch); and the pop-up's own: "lit" (five letters, "1" lit,
## "t" the blue of a television: the window nearer the door, the other one,
## the bay, the sash over the door, the transom), "curtain" (a colour),
## "blinds", "porch_light", "screens", "pots", "chairs", "fern".
static func porch_house(p: Node3D, b: int, u0: float, d: float, w: float, h: Dictionary) -> Node3D:
	var g := face(p, b, u0, d)
	var wall: Variant = h["wall"]
	var trim: Color = h.get("trim", WHITE)
	var height: float = h.get("height", 8.0)
	var deep: float = h.get("deep", 9.0)
	var porch: bool = h.get("porch", true)
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
	fb(g, 0.0, w, 0.0, height, -deep, 0.0, wall)
	fb(g, 0.0, w, height, height + 0.04, -deep, -0.36, TAR)
	if not porch:
		fb(g, 0.0, w, 0.0, F0 - 0.04, 0.0, 0.04, BASE)
	if h.get("chimney", false):
		var cs := w - 0.6 if door_left else 0.6
		fb(g, cs - 0.35, cs + 0.35, height, height + 1.3, -6.4, -5.9, wall)
		fb(g, cs - 0.4, cs + 0.4, height + 1.3, height + 1.38, -6.45, -5.85, CONCRETE)

	# The ground floor: the windows, the door.
	for i in wins.size():
		var s: float = wins[i]
		sash(g, s, F0 + 0.7, 0.95, 1.7, trim, _lit(lit, i), curtain, lintel, h.get("blinds", false))
		if h.get("screens", false):
			painted_screen(g, s, F0 + 0.7, 0.95, 1.7)
	_door(g, door_s, h)

	# The porch, or a marble stoop.
	if porch:
		_porch(g, w, door_s, into, h)
	else:
		_stoop(g, door_s, into, h)

	# Upstairs: the bay, the sash over the door, the cornice.
	var kind: String = h.get("bay", "white")
	var bay: Array = BAYS[kind]
	var bay_s := w * (0.66 if door_left else 0.34)
	var base := PROOF + 0.05 if porch else 4.3
	var top := height - 0.65 - 0.205
	var sh := minf(1.72, top - 0.22 - base - 0.5)
	var sz := top - 0.22 - sh
	_bay(g, bay_s, bay, kind, base, top, sz, sh, _lit(lit, 2), curtain, porch)
	sash(g, door_s, top - 0.22 - 1.65, 0.95, 1.65, trim, _lit(lit, 3), curtain)
	_cornice(g, w, height, trim, bay_s, bay[0])
	return g


static func _lit(lit: String, i: int) -> Variant:
	if i >= lit.length():
		return null
	match lit[i]:
		"1":
			return LIT
		"t":
			return TV
	return null


static func _door(g: Node3D, s: float, h: Dictionary) -> void:
	var trim: Color = h.get("trim", WHITE)
	var leaf: Color = h.get("door", DOORS["red"])
	fb(g, s - 0.62, s + 0.62, F0, F0 + 2.78, 0.0, 0.05, trim)
	fb(g, s - 0.48, s + 0.48, F0, F0 + 2.16, 0.05, 0.085, leaf)
	for y: float in [F0 + 0.25, F0 + 1.2]:
		fb(g, s - 0.36, s + 0.36, y, y + 0.75, 0.085, 0.1, leaf.lightened(0.14))
	fb(g, s - 0.48, s + 0.48, F0 + 2.26, F0 + 2.66, 0.05, 0.075, Kit.flat(LIT, 0.85) if _lit(h.get("lit", ""), 4) != null else PANE)
	Props.words(g, h.get("no", ""), Vector3(s, F0 + 2.46, 0.082), 0.2, GOLD)
	var knob := s + (0.32 if h.get("door_left", true) else -0.32)
	fb(g, knob - 0.04, knob + 0.04, F0 + 1.0, F0 + 1.08, 0.1, 0.14, GOLD)


static func _porch(g: Node3D, w: float, door_s: float, into: float, h: Dictionary) -> void:
	var trim: Color = h.get("trim", WHITE)
	var gap := [door_s - 0.66, door_s + 0.66]
	var posts := [0.16, w * 0.5, w - 0.16]
	# The deck: one solid grey box, the width of the house.
	fb(g, 0.0, w, 0.0, F0, 0.0, PD, PORCH)
	# Posts, the flat roof on them, a fascia in the trim colour.
	for s: float in posts:
		fb(g, s - 0.1, s + 0.1, F0, CEIL, PD - 0.33, PD - 0.13, trim)
	fb(g, 0.0, w, CEIL, PROOF, 0.0, PD + 0.18, PORCH_ROOF)
	fb(g, 0.006, w - 0.006, CEIL - 0.24, CEIL + 0.06, PD + 0.06, PD + 0.2, trim)
	# The railing, its opening at the steps with a newel either side.
	for i in 2:
		for span: Array in _cut([posts[i] + 0.1, posts[i + 1] - 0.1], gap):
			var a: float = span[0]
			var c: float = span[1]
			if absf(c - gap[0]) < 0.001:
				fb(g, c - 0.13, c, F0, F0 + 1.0, PD - 0.31, PD - 0.15, trim)
				c -= 0.13
			if absf(a - gap[1]) < 0.001:
				fb(g, a, a + 0.13, F0, F0 + 1.0, PD - 0.31, PD - 0.15, trim)
				a += 0.13
			fb(g, a, c, F0 + 0.82, F0 + 0.93, PD - 0.28, PD - 0.18, trim)
			fb(g, a, c, F0 + 0.1, F0 + 0.18, PD - 0.27, PD - 0.19, trim)
			var n := maxi(int((c - a) / 0.3), 1)
			for j in n:
				var x: float = a + (j + 0.5) * (c - a) / n
				fb(g, x - 0.035, x + 0.035, F0 + 0.18, F0 + 0.82, PD - 0.26, PD - 0.2, trim)
	for s: float in [0.08, w - 0.08]:
		fb(g, s - 0.05, s + 0.05, F0 + 0.82, F0 + 0.93, 0.0, PD - 0.33, trim)
	# The steps down, the same grey.
	for k in 3:
		fb(g, door_s - 0.625, door_s + 0.625, 0.0, F0 - RISE * (k + 1), PD + 0.3 * k, PD + 0.3 * (k + 1), PORCH)
	# The porch light, under the roof's front edge over the steps.
	var on: bool = h.get("porch_light", false)
	fb(g, door_s - 0.09, door_s + 0.09, CEIL - 0.05, CEIL, PD - 0.45, PD - 0.27, IRON)
	Kit.ball(g, 0.1, Vector3(door_s, CEIL - 0.13, PD - 0.36), Kit.flat(Color(1.0, 0.86, 0.55), 1.8) if on else Color(0.62, 0.6, 0.55), 8)
	if on:
		Kit.omni(g, Vector3(door_s, CEIL - 0.35, PD + 0.2), Color(1.0, 0.84, 0.58), 2.4, 5.5)
	# The pop-up's own: things on the porch.
	if h.get("chairs", false):
		var cs := w * 0.5 + into * 1.2
		porch_chair(g, cs - 0.4, 0.8, Color(0.4, 0.75, 0.7), 12.0)
		porch_chair(g, cs + 0.4, 0.8, Color(0.95, 0.55, 0.5), -8.0)
	if h.get("fern", false):
		for s: float in [w * 0.5 - 0.6, w * 0.5 + 0.6]:
			Kit.cyl(g, 0.006, 0.45, Vector3(s, CEIL - 0.22, PD - 0.45), IRON, Vector3.ZERO, 4)
			Kit.cyl(g, 0.16, 0.14, Vector3(s, CEIL - 0.5, PD - 0.45), Color(0.6, 0.35, 0.22), Vector3.ZERO, 8, 0.12)
			Kit.ball(g, 0.26, Vector3(s, CEIL - 0.5, PD - 0.45), Color(0.28, 0.58, 0.26), 7)
	if h.get("pots", false):
		for j in 3:
			var ps := door_s + into * (0.95 + j * 0.42)
			Kit.cyl(g, 0.13, 0.24, Vector3(ps, F0 + 0.12, PD - 0.55), Color(0.72, 0.38, 0.24), Vector3.ZERO, 8, 0.1)
			Kit.ball(g, 0.15, Vector3(ps, F0 + 0.33, PD - 0.55), [Color(0.9, 0.25, 0.35), Color(0.95, 0.8, 0.2), Color(0.85, 0.4, 0.75)][j], 6)


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
	# A marble stoop, white as scrubbed: a landing at the door and four risers down, no rail.
	fb(g, door_s - 0.7, door_s + 0.7, 0.0, F0, -0.01, 0.45, MARBLE)
	for k in 3:
		fb(g, door_s - 0.7, door_s + 0.7, 0.0, F0 - RISE * (k + 1), 0.45 + 0.3 * k, 0.45 + 0.3 * (k + 1), MARBLE)
	var lamp_s := door_s + into * 0.85
	var on: bool = h.get("porch_light", false)
	fb(g, lamp_s - 0.08, lamp_s + 0.08, F0 + 2.0, F0 + 2.32, 0.0, 0.04, IRON)
	Kit.box(g, Vector3(0.14, 0.24, 0.14), Vector3(lamp_s, F0 + 2.1, 0.12), Kit.flat(Color(1.0, 0.86, 0.55), 1.6) if on else Color(0.5, 0.48, 0.42))
	if on:
		Kit.omni(g, Vector3(lamp_s, F0 + 2.0, 0.8), Color(1.0, 0.84, 0.58), 2.0, 4.8)


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


## The cornice: a band 0.52 tall standing out 0.34 in the trim colour, a tar
## cap on it, brackets under it about every 1.6 m except over the bay.
static func _cornice(g: Node3D, w: float, height: float, trim: Color, bay_s: float, bay_w: float) -> void:
	fb(g, 0.0, w, height - 0.52, height - 0.2, 0.0, 0.2, trim)
	fb(g, 0.0, w, height - 0.2, height - 0.04, 0.0, 0.34, trim)
	fb(g, 0.0, w, height - 0.04, height + 0.02, 0.0, 0.28, TAR)
	var n := maxi(2, int(w / 1.6) + 1)
	for i in n:
		var s := 0.22 + i * (w - 0.44) / (n - 1)
		if absf(s - bay_s) < bay_w * 0.5 + 0.2:
			continue
		fb(g, s - 0.08, s + 0.08, height - 0.88, height - 0.52, 0.0, 0.27, trim)


## A metal shell-back porch chair, the kind every Baltimore porch had.
static func porch_chair(g: Node3D, s: float, t: float, paint: Color, turn := 8.0) -> void:
	var c := Kit.group(g, Vector3(s, F0, t), Vector3(0, turn, 0))
	Kit.box(c, Vector3(0.48, 0.05, 0.42), Vector3(0, 0.4, 0.02), paint)
	Kit.box(c, Vector3(0.5, 0.45, 0.05), Vector3(0, 0.68, -0.2), paint, Vector3(-12, 0, 0))
	var shell := Kit.ball(c, 0.25, Vector3(0, 0.88, -0.22), paint, 8)
	shell.scale = Vector3(1.0, 0.45, 0.2)
	for x: float in [-0.21, 0.21]:
		Kit.box(c, Vector3(0.035, 0.4, 0.035), Vector3(x, 0.2, 0.18), IRON)
		Kit.box(c, Vector3(0.035, 0.035, 0.42), Vector3(x, 0.02, 0.0), IRON)
		Kit.box(c, Vector3(0.04, 0.04, 0.34), Vector3(x + signf(x) * 0.02, 0.56, 0.02), paint)


## A plain stoop-front rowhouse (Old York Road's), on a face: a door and its
## marble steps, the windows, a cornice. lit: one letter per window ("1" lit),
## ground floor first, left to right.
static func plain_house(g: Node3D, w: float, height: float, wall: Variant, trim: Color, door: Color, lit := "", floors := 2, door_left := true) -> void:
	fb(g, 0.0, w, 0.0, height, -9.0, 0.0, wall)
	fb(g, 0.0, w, height, height + 0.04, -9.0, -0.36, TAR)
	fb(g, 0.0, w, 0.0, F0 - 0.04, 0.0, 0.04, BASE)
	var ds := 0.9 if door_left else w - 0.9
	fb(g, ds - 0.62, ds + 0.62, F0, F0 + 2.78, 0.0, 0.05, trim)
	fb(g, ds - 0.48, ds + 0.48, F0, F0 + 2.16, 0.05, 0.085, door)
	fb(g, ds - 0.48, ds + 0.48, F0 + 2.26, F0 + 2.66, 0.05, 0.075, Kit.flat(LIT, 0.8) if lit.length() > 0 and lit[0] == "1" else PANE)
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


# ------------------------------------------------------------ street pieces

## A street lamp as the old game's network lamps: a dark pole straight up to
## 4.68 m, a gooseneck, and a cobra head whose lens hangs out over the road.
## It stands 0.65 m behind the kerb; `reach` is from the pole to the lens
## (the head reaches towards +z: turn the group to aim it). Its light is a spot
## from the lens tipped a little back over the pavement, `energy` strong: a pool
## with a soft edge on the pavement and the kerbside (0: only the lens glows,
## for lamps far off up a road).
static func cobra_lamp(p: Node3D, b: int, u: float, v: float, yaw := 0.0, reach := 1.17, energy := 8.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.3, 0.3)
	var pole := Color(0.18, 0.18, 0.2)          # (42, 42, 46), a little lifted
	Kit.cyl(g, 0.11, 0.5, Vector3(0, 0.25, 0), pole, Vector3.ZERO, 8, 0.08)
	Kit.cyl(g, 0.065, 4.68, Vector3(0, 2.34, 0), pole, Vector3.ZERO, 8, 0.055)
	pipe(g, Vector3(0, 4.62, 0), Vector3(0, 4.98, 0.3), 0.05, pole)
	pipe(g, Vector3(0, 4.98, 0.3), Vector3(0, 5.04, reach - 0.25), 0.05, pole)
	Kit.bevel(g, Vector3(0.3, 0.17, 0.66), Vector3(0, 5.05, reach), Color(0.5, 0.52, 0.55), 0.05)
	Kit.bevel(g, Vector3(0.32, 0.07, 0.42), Vector3(0, 5.16, reach - 0.06), Color(0.42, 0.44, 0.47), 0.025)
	Kit.box(g, Vector3(0.24, 0.05, 0.46), Vector3(0, 4.945, reach + 0.04), Kit.flat(LAMP, 2.6))
	if energy > 0.0:
		var spot := SpotLight3D.new()
		spot.light_color = LAMP
		spot.light_energy = energy
		spot.spot_range = 9.5
		spot.spot_angle = 56.0
		spot.spot_angle_attenuation = 1.5
		spot.spot_attenuation = 0.6
		spot.position = Vector3(0, 4.88, reach)
		spot.rotation_degrees = Vector3(-76, 0, 0)
		g.add_child(spot)
	return g


## A wooden utility pole, as along Rose Hill's north kerb: 9.6 m tall, a 2 m
## cross-arm at 8.93 m with three insulators for the wires, which run along u.
## `transformer`: a grey transformer can hung on its street side.
static func utility_pole(p: Node3D, b: int, u: float, v: float, transformer := false) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.36, 0.36)
	var wood := Color(0.48, 0.39, 0.29)         # (118, 94, 69)
	Kit.cyl(g, 0.15, 9.6, Vector3(0, 4.8, 0), wood, Vector3.ZERO, 8, 0.11)
	Kit.box(g, Vector3(0.12, 0.12, 2.0), Vector3(0, 8.93, 0), wood)
	for z: float in WIRES:
		Kit.cyl(g, 0.045, 0.2, Vector3(0, 9.09, z), Color(0.5, 0.62, 0.55), Vector3.ZERO, 6)
	for y: float in [1.6, 2.1]:
		Kit.box(g, Vector3(0.16, 0.012, 0.012), Vector3(0, y, 0.15), Color(0.7, 0.7, 0.68))   # old staples, a tag
	Kit.box(g, Vector3(0.12, 0.16, 0.012), Vector3(0, 2.6, 0.151), Color(0.85, 0.8, 0.3))
	if transformer:
		var can := Color(0.52, 0.55, 0.57)
		Kit.box(g, Vector3(0.1, 0.6, 0.2), Vector3(0, 7.6, 0.22), can.darkened(0.25))
		Kit.cyl(g, 0.3, 0.9, Vector3(0, 7.6, 0.45), can, Vector3.ZERO, 10)
		Kit.cyl(g, 0.33, 0.08, Vector3(0, 8.07, 0.45), can.darkened(0.15), Vector3.ZERO, 10)
		pipe(g, Vector3(0, 8.11, 0.45), Vector3(0, 8.95, 0.8), 0.014, Props.DARK, 4)
	return g


## Where the three wires sit across a pole's cross-arm (along v).
const WIRES := [-0.8, 0.0, 0.8]


## The old game's everyday parked kinds, kept chunky. kind: "box_sedan" (the
## big square 1980s sedan), "compact", "minivan", "midsize", "hatchback",
## "long_sedan". Every one fits the old game's 2.12 x 4.70 m parking envelope.
const CAR_KINDS := {
	# length, width, body height, cabin length, cabin offset (+ towards the front), cabin height
	"box_sedan": [4.7, 1.86, 0.6, 2.05, -0.22, 0.5],
	"compact": [4.2, 1.72, 0.55, 2.0, -0.18, 0.5],
	"minivan": [4.6, 1.86, 0.72, 3.15, -0.42, 0.66],
	"midsize": [4.5, 1.8, 0.58, 2.15, -0.15, 0.5],
	"hatchback": [3.95, 1.72, 0.58, 2.05, -0.55, 0.54],
	"long_sedan": [4.7, 1.84, 0.56, 2.15, -0.28, 0.48],
}


## A parked car; its front is the front (turn it with `yaw`). Chunky and
## toy-like: a rounded body, a glasshouse with a raked windscreen and back
## window under a roof, the pillars, a grille and lamps, bumpers and plates,
## dark wheel wells. `ground`: the height of the road under it.
static func parked_car(p: Node3D, b: int, u: float, v: float, yaw: float, kind: String, paint: Color, ground := 0.0) -> Node3D:
	var c: Array = CAR_KINDS[kind]
	var car: Node3D = p.prop(b, u, v, yaw, c[1], c[0])
	car_model(car, Vector3(0, ground, 0), 0.0, kind, paint)
	return car


## The car itself (see parked_car) built into `parent` at `at` (the road under
## it), its front facing `yaw`. It takes no floor: for cars in streets nobody
## walks.
static func car_model(parent: Node3D, at: Vector3, yaw: float, kind: String, paint: Color) -> Node3D:
	var c: Array = CAR_KINDS[kind]
	var l: float = c[0]
	var w: float = c[1]
	var bh: float = c[2]
	var cl: float = c[3]
	var cz: float = c[4]
	var ch: float = c[5]
	var g := Kit.group(parent, at, Vector3(0, yaw, 0))
	var glass := Color(0.16, 0.21, 0.28)
	var chrome := Color(0.78, 0.8, 0.82)
	var rubber := Color(0.07, 0.07, 0.08)
	var seam := paint.darkened(0.45)
	var old := kind == "box_sedan" or kind == "long_sedan"
	var van := kind == "minivan"
	var floor_y := 0.3
	var top := floor_y + bh
	# The body, the old boxy sedans squarer.
	Kit.bevel_block(g, Vector3(w, bh, l), Vector3(0, floor_y, 0), paint, 0.05 if old else 0.11)
	# The glasshouse: the glass sides, the raked windscreen and back window (a
	# minivan's and a hatchback's back is near upright), the roof on top (a
	# cream vinyl one on the long sedan), the pillars.
	var cw := w - (0.16 if van else 0.22)
	var rf := 0.42 if van else 0.55
	var rb := 0.14 if van or kind == "hatchback" else 0.42
	var zf := cz + cl * 0.5
	var zb := cz - cl * 0.5
	var mid := cl - rf - rb
	var mz := (zf - rf + zb + rb) * 0.5
	var gy := top + ch * 0.5
	Kit.box(g, Vector3(cw, ch, mid), Vector3(0, gy, mz), glass)
	Kit.prism(g, Vector3(rf, ch, cw), Vector3(0, gy, zf - rf * 0.5), glass, Vector3(0, 90, 0), 1.0)
	Kit.prism(g, Vector3(rb, ch, cw), Vector3(0, gy, zb + rb * 0.5), glass, Vector3(0, 90, 0), 0.0)
	Kit.bevel(g, Vector3(cw + 0.06, 0.08, mid + 0.12), Vector3(0, top + ch + 0.03, mz), Color(0.9, 0.87, 0.78) if kind == "long_sedan" else paint, 0.03)
	for s: float in [-1.0, 1.0]:
		var x := s * (cw * 0.5 + 0.006)
		Kit.tube(g, Vector3(x, top, zf), Vector3(x, top + ch, zf - rf), 0.04, paint, 4)
		Kit.tube(g, Vector3(x, top, zb), Vector3(x, top + ch, zb + rb), 0.04, paint, 4)
		Kit.box(g, Vector3(0.02, ch, 0.12), Vector3(s * (cw * 0.5 + 0.012), gy, mz), paint)
		Kit.bevel(g, Vector3(0.1, 0.09, 0.07), Vector3(s * (cw * 0.5 + 0.09), top + 0.1, zf - 0.08), paint, 0.02)   # a mirror
		# Along the side: a trim strip (chrome on the old ones), the door seams.
		Kit.box(g, Vector3(0.02, 0.05, l - 0.8), Vector3(s * (w * 0.5 + 0.005), floor_y + bh * 0.55, 0), chrome if old else seam)
		var seams: Array = [zf - 0.05, mz - 0.3] if van else [zf - 0.05, mz, zb + rb - 0.05]
		for z: float in seams:
			Kit.box(g, Vector3(0.012, bh * 0.78, 0.02), Vector3(s * (w * 0.5 + 0.004), floor_y + bh * 0.5, z), seam)
	if van:     # a roof rack
		for x: float in [-cw * 0.36, cw * 0.36]:
			Kit.box(g, Vector3(0.05, 0.05, mid - 0.1), Vector3(x, top + ch + 0.1, mz), Color(0.2, 0.2, 0.22))
	# The front: a grille (chrome bars on the old ones), the lamps; the tail lamps.
	var nose := l * 0.5 + 0.006
	var ly := top - bh * 0.42
	Kit.box(g, Vector3(w * 0.42, bh * 0.4, 0.02), Vector3(0, ly, nose), Color(0.12, 0.12, 0.14))
	if old:
		for k in 3:
			Kit.box(g, Vector3(w * 0.42, 0.025, 0.02), Vector3(0, ly - bh * 0.12 + k * bh * 0.12, nose + 0.012), chrome)
	for x: float in [-w * 0.5 + 0.3, w * 0.5 - 0.3]:
		Kit.box(g, Vector3(0.3, 0.14, 0.02), Vector3(x, ly, nose), Kit.flat(Color(0.98, 0.95, 0.8), 0.35))
		Kit.box(g, Vector3(0.32, 0.14, 0.02), Vector3(x, top - bh * 0.35, -nose), Kit.flat(Color(0.85, 0.12, 0.1), 0.45))
	# The bumpers, chrome on the old ones, and the plates on them.
	for s: float in [1.0, -1.0]:
		Kit.bevel(g, Vector3(w + 0.06, 0.17, 0.16), Vector3(0, floor_y + 0.1, s * (l * 0.5 + 0.02)), chrome if old else Color(0.22, 0.22, 0.24), 0.05)
		Kit.box(g, Vector3(0.38, 0.14, 0.02), Vector3(0, floor_y + 0.1, s * (l * 0.5 + 0.105)), Color(0.94, 0.93, 0.86))
	# The wheels: a dark well behind each, the tyre, a hubcap, the hub.
	for x: float in [-w * 0.5 + 0.08, w * 0.5 - 0.08]:
		for z: float in [-l * 0.5 + 0.85, l * 0.5 - 0.85]:
			Kit.cyl(g, 0.41, 0.03, Vector3(signf(x) * (w * 0.5 + 0.004), 0.36, z), rubber, Vector3(0, 0, 90), 12)
			Kit.cyl(g, 0.32, 0.24, Vector3(x, 0.32, z), rubber, Vector3(0, 0, 90), 12)
			Kit.cyl(g, 0.17, 0.25, Vector3(x, 0.32, z), chrome, Vector3(0, 0, 90), 8)
			Kit.cyl(g, 0.06, 0.26, Vector3(x, 0.32, z), Color(0.3, 0.3, 0.33), Vector3(0, 0, 90), 6)
	return g


## The watcher that fades the parked cars that would hide him (see CarFade):
## hand it each car as it is parked.
static func car_fade(p: Node3D, b: int) -> CarFade:
	var f := CarFade.new()
	f.name = "CarFade"
	p.node_of(b).add_child(f)
	p.watchers.append(f)
	return f


## The parked cars stand between the camera and the pavement, so any car that
## would hide him fades to a ghost of itself until he has walked on. The place
## tells it where he is (place.watchers), or it finds him (main.gd's "Player")
## when it has not been told yet; it finds the camera itself, each frame.
class CarFade extends Node3D:
	const GHOST := 0.2            # how much of a car still shows while it is in the way
	const SPEED := 5.0            # a whole fade in a fifth of a second
	var _cars: Array = []         # [the car, its box in its own space, its own materials, how much shows]
	var _at := Vector3.INF
	var _eye := Vector3.INF
	var _lead: Node3D = null

	## A car to look after: its parts get materials of their own, so it fades alone.
	func add(car: Node3D) -> void:
		var mats := {}
		var box := AABB()
		var first := true
		for node: Node in car.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			var xf := mi.transform
			var up := mi.get_parent()
			while up != car and up is Node3D:
				xf = (up as Node3D).transform * xf
				up = up.get_parent()
			var part: AABB = xf * mi.mesh.get_aabb()
			box = part if first else box.merge(part)
			first = false
			var m := mi.material_override as StandardMaterial3D
			if m == null:
				continue
			if not mats.has(m):
				var own := m.duplicate() as StandardMaterial3D
				own.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				own.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
				mats[m] = own
			mi.material_override = mats[m]
		_cars.append([car, box.grow(0.1), mats.values(), 1.0])

	func watch(at: Vector3, _delta: float) -> void:
		_at = at

	func _process(delta: float) -> void:
		var cam := get_viewport().get_camera_3d()
		if cam == null or not is_visible_in_tree():
			return
		if _lead == null and get_tree().current_scene:
			_lead = get_tree().current_scene.get_node_or_null("Player") as Node3D
		if _lead:
			_at = _lead.global_position
		if _at == Vector3.INF:
			return
		var eye := cam.global_position
		var cut := _eye == Vector3.INF or eye.distance_to(_eye) > 2.0     # the camera jumped: no fading, just be right
		_eye = eye
		var near := eye.distance_to(_at) < 16.0                            # the game camera, not a view of the whole street
		for car: Array in _cars:
			var box: AABB = (car[0] as Node3D).global_transform * (car[1] as AABB)
			var hides := false
			if near:
				for o: Vector3 in [Vector3(0, 0.1, 0), Vector3(-0.4, 0.1, 0), Vector3(0.4, 0.1, 0), Vector3(0, 0.8, 0), Vector3(0, 1.5, 0)]:
					if box.intersects_segment(eye, _at + o) != null:
						hides = true
						break
			var want := GHOST if hides else 1.0
			var a: float = want if cut else move_toward(float(car[3]), want, delta * SPEED)
			if a != float(car[3]):
				car[3] = a
				for m: StandardMaterial3D in car[2]:
					var col := m.albedo_color
					col.a = a
					m.albedo_color = col


## A blue mailbox on its four legs, the slot under the round top.
static func mailbox(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.56, 0.5)
	var blue := Color(0.16, 0.32, 0.66)
	for x: float in [-0.21, 0.21]:
		for z: float in [-0.18, 0.18]:
			Kit.box(g, Vector3(0.05, 0.3, 0.05), Vector3(x, 0.15, z), IRON)
	Kit.block(g, Vector3(0.5, 0.75, 0.44), Vector3(0, 0.3, 0), blue)
	Kit.cyl(g, 0.22, 0.5, Vector3(0, 1.05, 0), blue, Vector3(0, 0, 90), 12)
	Kit.box(g, Vector3(0.34, 0.08, 0.03), Vector3(0, 0.96, 0.235), Color(0.6, 0.62, 0.64))
	Kit.box(g, Vector3(0.4, 0.26, 0.012), Vector3(0, 0.62, 0.226), Color(0.95, 0.95, 0.92))
	Props.words(g, "MAIL", Vector3(0, 0.62, 0.234), 0.13, blue.darkened(0.2))
	return g


## A bus-stop sign on its pole; the plate faces along the kerb.
static func bus_stop(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.2, 0.2)
	Kit.cyl(g, 0.035, 2.95, Vector3(0, 1.475, 0), Color(0.55, 0.57, 0.6), Vector3.ZERO, 6)
	Kit.box(g, Vector3(0.52, 0.68, 0.03), Vector3(0, 2.5, 0), Color(0.95, 0.95, 0.92))
	Kit.box(g, Vector3(0.46, 0.2, 0.036), Vector3(0, 2.68, 0), Color(0.15, 0.35, 0.72))
	for side: float in [1.0, -1.0]:
		Props.words(g, "BUS", Vector3(0, 2.68, 0.02 * side), 0.13, Color(0.97, 0.97, 0.95), 0.0 if side > 0 else 180.0)
		Props.words(g, "STOP", Vector3(0, 2.4, 0.017 * side), 0.13, Color(0.15, 0.35, 0.72), 0.0 if side > 0 else 180.0)
	return g


## The corner's sign post: a white-on-green blade for each street, worded on
## both faces (`along_u` names the street running left to right, `along_v` the
## one running away), and under them a stop sign facing `stop_yaw`.
static func street_sign(p: Node3D, b: int, u: float, v: float, along_u: String, along_v: String, stop_yaw := 270.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.2, 0.2)
	var green := Color(0.1, 0.42, 0.24)
	var white := Color(0.96, 0.96, 0.92)
	# The pole stops under the blades, which sit on it one across the other.
	Kit.cyl(g, 0.04, 2.74, Vector3(0, 1.37, 0), Color(0.55, 0.57, 0.6), Vector3.ZERO, 6)
	Kit.box(g, Vector3(0.1, 0.03, 0.1), Vector3(0, 2.735, 0), Color(0.55, 0.57, 0.6))
	Kit.box(g, Vector3(1.3, 0.22, 0.03), Vector3(0, 2.86, 0), green)
	Kit.box(g, Vector3(0.06, 0.024, 0.06), Vector3(0, 2.982, 0), Color(0.55, 0.57, 0.6))
	Kit.box(g, Vector3(0.03, 0.22, 1.3), Vector3(0, 3.104, 0), green)
	for side: float in [1.0, -1.0]:
		Props.words(g, along_u, Vector3(0, 2.86, 0.017 * side), 0.12, white, 0.0 if side > 0 else 180.0)
		Props.words(g, along_v, Vector3(0.017 * side, 3.104, 0), 0.12, white, 90.0 * side)
	# The stop sign: a grey back, the red face, the white border, the word.
	var stop := Kit.group(g, Vector3(0, 2.2, 0), Vector3(0, stop_yaw, 0))
	var oct := Kit.group(stop, Vector3.ZERO, Vector3(0, 0, 22.5))      # a flat side on top
	Kit.disc(oct, 0.34, Vector3(0, 0, 0.05), Color(0.6, 0.62, 0.64), 0.01, 8)
	Kit.disc(oct, 0.335, Vector3(0, 0, 0.06), Color(0.8, 0.12, 0.1), 0.012, 8)
	Kit.disc(oct, 0.3, Vector3(0, 0, 0.069), Color(0.95, 0.94, 0.9), 0.01, 8)
	Kit.disc(oct, 0.27, Vector3(0, 0, 0.077), Color(0.8, 0.12, 0.1), 0.01, 8)
	Props.words(stop, "STOP", Vector3(0, 0, 0.087), 0.15, Color(0.97, 0.97, 0.95))
	return g


## A scrap of litter (decoration: it does not block): a paper, a can, a cup.
static func litter(parent: Node3D, pos: Vector3, n: int) -> void:
	match n % 3:
		0:
			Kit.box(parent, Vector3(0.22, 0.008, 0.28), pos + Vector3(0, 0.006, 0), Color(0.92, 0.9, 0.84), Vector3(0, n * 37.0, 0))
		1:
			Kit.cyl(parent, 0.033, 0.12, pos + Vector3(0, 0.033, 0), [Color(0.8, 0.15, 0.15), Color(0.2, 0.4, 0.8), Color(0.85, 0.85, 0.85)][int(n / 3.0) % 3], Vector3(90, n * 53.0, 0), 8)
		_:
			Kit.cyl(parent, 0.045, 0.11, pos + Vector3(0, 0.045, 0), Color(0.95, 0.95, 0.92), Vector3(90, n * 71.0, 0), 8, 0.035)


## Black rubbish bags heaped by a can (decoration: they do not block).
static func bags(parent: Node3D, pos: Vector3, n := 2) -> void:
	for i in n:
		var bag := Kit.ball(parent, 0.26, pos + Vector3(i * 0.38 - 0.19, 0.2, (i % 2) * 0.12), Color(0.08, 0.08, 0.1), 7)
		bag.scale = Vector3(1.0, 0.8, 0.9)
		Kit.cyl(parent, 0.05, 0.12, pos + Vector3(i * 0.38 - 0.19, 0.42, (i % 2) * 0.12), Color(0.08, 0.08, 0.1), Vector3.ZERO, 5)
