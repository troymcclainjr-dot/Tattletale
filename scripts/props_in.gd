extends RefCounted
## Architecture and room dressing for the places built from floor plans: what
## makes a wall more than one flat texture from floor to top, a floor more than
## one colour, and a street front more than a slab.
##
##   const In := preload("res://scripts/props_in.gd")
##   In.dress(p, b, true, 17.0, 1.0, 0.075, 10.425, openings, style)
##   In.picture(p, b, 2.0, 17.08, 0.0, 0.8, 0.6, "sea")
##
## Things on a wall take, as in props.gd, the point on the wall's face and the
## way the wall faces (`yaw`: 0 the street, 90 right, 180 the back, 270 left).
## Runs of trim take the wall itself, as place.gd's `cross` and `side` do: which
## way it runs (`along_u`), where it stands (`at`: its middle line), the side
## that is dressed (`face`: +1 the street or right-hand side, -1 the back or
## left-hand side), where the run starts and ends, and the openings the wall was
## built with, so the trim stops at each door and runs under and over each
## window. `b` is a band (its node is used) or a node to build in (a front wall,
## for the street face). Nothing here takes floor space.

const Props := preload("res://scripts/props.gd")

const T := 0.15              # place.gd's wall thickness
const FRAME := 0.055         # how far a door or window frame reaches past its opening (place.gd's _run)
const SURROUND := 0.09       # how wide an architrave is
const SKIN := 0.009          # paint, paper or panelling over a wall stands this far off its face
const WARM := Color(1.0, 0.86, 0.6)
const TUBE := Color(0.94, 0.98, 1.0)
const BRASS := Color(0.78, 0.62, 0.28)


static func _node(p: Node3D, b: Variant) -> Node3D:
	return b if b is Node3D else p.node_of(int(b))


## A box standing out from a wall's face by `d`, from a to b along the wall and
## y0 to y1 high. `plane` is the face itself. `back` sinks its back that far into
## the wall, so pieces laid over one another never share a back face.
static func _out(p: Node3D, n: Node3D, along_u: bool, plane: float, face: float, a: float, b: float, y0: float, y1: float, d: float, look: Variant, back := 0.0) -> MeshInstance3D:
	return p.slab(n, along_u, plane + face * (d - back) * 0.5, a, b, y0, y1, d + back, look)


## The pieces of a band of trim from y0 to y1 along a wall, from..to, round the
## wall's openings: a list of [a, b, y0, y1]. A door cuts the band from the floor
## to over its frame; a window from under its sill to over its head. `pad`: how
## far round each frame the cut reaches (its surround); `stool`: how much more
## under a window's sill (its sill board). An opening marked "bare" has no
## surround, so the band runs right up to its frame.
static func _band(from: float, to: float, openings: Array, y0: float, y1: float, pad := 0.0, stool := 0.0) -> Array:
	var edges: Array = [from, to]
	var cuts: Array = []
	for op: Dictionary in openings:
		var kind: String = op.get("kind", "door")
		var sill: float = op.get("sill", 0.95 if kind == "window" else 0.0)
		var head: float = op.get("head", 2.1 if kind == "window" else (2.3 if kind == "arch" else 2.05))
		var bare: bool = op.get("bare", false)
		var lo := sill - FRAME - (0.0 if bare else stool) if sill > 0.0 else -1.0
		var hi := head + FRAME + (0.0 if bare else pad)
		var a: float = float(op["a"]) - FRAME - (0.0 if bare else pad)
		var e: float = float(op["b"]) + FRAME + (0.0 if bare else pad)
		if y1 <= lo or y0 >= hi or e <= from or a >= to:
			continue
		cuts.append([a, e, lo, hi])
		for x: float in [a, e]:
			if x > from and x < to:
				edges.append(x)
	edges.sort()
	var out: Array = []
	for i in edges.size() - 1:
		var a: float = edges[i]
		var e: float = edges[i + 1]
		if e - a < 0.015:
			continue
		var mid := (a + e) * 0.5
		var spans: Array = [[y0, y1]]
		for c: Array in cuts:
			if mid <= c[0] or mid >= c[1]:
				continue
			var left: Array = []
			for s: Array in spans:
				if s[1] <= c[2] or s[0] >= c[3]:
					left.append(s)
					continue
				if s[0] < c[2]:
					left.append([s[0], c[2]])
				if s[1] > c[3]:
					left.append([c[3], s[1]])
			spans = left
		for s: Array in spans:
			if s[1] - s[0] < 0.02:
				continue
			var joined := false
			for o: Array in out:
				if absf(o[1] - a) < 0.001 and absf(o[2] - s[0]) < 0.001 and absf(o[3] - s[1]) < 0.001:
					o[1] = e
					joined = true
					break
			if not joined:
				out.append([a, e, s[0], s[1]])
	return out


static func _skin(p: Node3D, n: Node3D, along_u: bool, plane: float, face: float, from: float, to: float, openings: Array, y0: float, y1: float, pad: float, stool: float, look: Variant) -> void:
	if y1 - y0 < 0.02:
		return
	for s: Array in _band(from, to, openings, y0, y1, pad, stool):
		_out(p, n, along_u, plane, face, s[0], s[1], s[2], s[3], SKIN, look)


## Dress one face of a wall. style (all optional):
##   "lower"    a look for the wall below the dado: paint, tiles, panelling
##   "upper"    a look for the wall above it (up to the picture rail, if any)
##   "dado"     a colour: a rail at "dado_y" (1.0) between the two; "dado_h"
##              (0.065) and "dado_d" (0.032) make it a deeper bumper rail, and
##              "dado_line" (a colour) runs a line along its middle
##   "bands"    stripes of paint over the dado: a list of [look, height], laid
##              one over the other from "bands_y" (else right over the dado)
##   "rail"     a colour: a picture rail at "rail_y" (2.42)
##   "frieze"   a look for the wall over the picture rail
##   "skirt"    a colour: a skirting board, "skirt_h" high (0.16)
##   "cornice"  a colour: a moulding along the top of the wall
##   "surround" a colour: an architrave round each door and window, and
##   "stool"    a colour for the sill board under each window (else the surround's)
##   "h"        the wall's height (the place's wall_h); "t" its thickness (0.15)
static func dress(p: Node3D, b: Variant, along_u: bool, at: float, face: float, from: float, to: float, openings := [], style := {}) -> void:
	var n := _node(p, b)
	var t: float = style.get("t", T)
	var plane := at + face * t * 0.5
	var wall_top: float = float(style.get("h", p.wall_h))
	var h := wall_top - (0.0 if along_u else 0.01)          # side walls stop 1 cm under the cross walls (place.gd)
	var framed := style.has("surround")
	var pad := SURROUND if framed else 0.0
	var stool := 0.05 if framed else 0.0
	var dado_y: float = style.get("dado_y", 1.0)
	var dado_lo := dado_y - 0.02
	var dado_hi := dado_lo + float(style.get("dado_h", 0.065))
	var rail_y: float = style.get("rail_y", 2.42)
	var has_dado := style.has("dado")
	var has_rail := style.has("rail")
	# The layers meet edge to edge and never lie one over another (two faces in
	# one plane flicker): the paint stops on the skirting, under and over the
	# dado rail, under and over each band, under the picture rail and under the cornice.
	var base: float = style.get("skirt_h", 0.16) if style.has("skirt") else 0.0
	var top := wall_top - 0.17 if style.has("cornice") else h
	var lower: Variant = style.get("lower", style.get("upper") if has_dado else null)
	var up_from := base
	if lower != null:
		_skin(p, n, along_u, plane, face, from, to, openings, base, dado_lo if has_dado else dado_y, pad, stool, lower)
		up_from = dado_hi if has_dado else dado_y
	var up_to := rail_y if (has_rail or style.has("frieze")) else top
	var bands: Array = style.get("bands", [])
	if bands.size() > 0:
		var y := maxf(float(style.get("bands_y", up_from)), up_from)
		if style.has("upper"):
			_skin(p, n, along_u, plane, face, from, to, openings, up_from, y, pad, stool, style["upper"])
		for band: Array in bands:
			_skin(p, n, along_u, plane, face, from, to, openings, y, y + float(band[1]), pad, stool, band[0])
			y += float(band[1])
		up_from = y
	if style.has("upper"):
		_skin(p, n, along_u, plane, face, from, to, openings, up_from, up_to, pad, stool, style["upper"])
	if style.has("frieze"):
		_skin(p, n, along_u, plane, face, from, to, openings, rail_y + (0.045 if has_rail else 0.0), top, pad, stool, style["frieze"])
	if style.has("dado"):
		var dd: float = style.get("dado_d", 0.032)
		for s: Array in _band(from, to, openings, dado_lo, dado_hi, pad, stool):
			if s[3] - s[2] > dado_hi - dado_lo - 0.005:
				_out(p, n, along_u, plane, face, s[0], s[1], s[2], s[3], dd, style["dado"])
				if style.has("dado_line") and s[1] - s[0] > 0.06:      # its ends and its back kept off the rail's
					var mid: float = (s[2] + s[3]) * 0.5
					_out(p, n, along_u, plane, face, s[0] + 0.012, s[1] - 0.012, mid - 0.014, mid + 0.014, dd + 0.006, style["dado_line"], 0.004)
	if style.has("rail"):
		for s: Array in _band(from, to, openings, rail_y, rail_y + 0.045, pad, stool):
			if s[3] - s[2] > 0.04:
				_out(p, n, along_u, plane, face, s[0], s[1], s[2], s[3], 0.026, style["rail"])
	if style.has("skirt"):
		var sh: float = style.get("skirt_h", 0.16)
		for s: Array in _band(from, to, openings, 0.0, sh, pad, stool):
			if s[3] - s[2] > sh - 0.005:
				_out(p, n, along_u, plane, face, s[0], s[1], 0.0, sh - 0.03, 0.024, style["skirt"])
				_out(p, n, along_u, plane, face, s[0], s[1], sh - 0.03, sh, 0.032, style["skirt"])
	if style.has("cornice"):      # at the same heights on every wall, so the mouldings meet in the corners
		var c: Color = style["cornice"]
		_out(p, n, along_u, plane, face, from, to, wall_top - 0.17, wall_top - 0.1, 0.028, c)
		_out(p, n, along_u, plane, face, from, to, wall_top - 0.1, wall_top - 0.045, 0.058, c.darkened(0.12))
		_out(p, n, along_u, plane, face, from, to, wall_top - 0.045, h, 0.092, c)
	if framed:
		surrounds(p, n, along_u, at, face, from, to, openings, style["surround"], style.get("stool", null), t)


## An architrave round each door, arch and window of a wall (on its `face`
## side), from..to along it: a flat band standing proud of the frame; and
## under each window a deep sill board (`stool`, else the same colour) and an apron.
static func surrounds(p: Node3D, b: Variant, along_u: bool, at: float, face: float, from: float, to: float, openings: Array, look: Variant, stool: Variant = null, t := T) -> void:
	var n := _node(p, b)
	var plane := at + face * t * 0.5
	for op: Dictionary in openings:
		var a: float = op["a"]
		var e: float = op["b"]
		if e < from or a > to or op.get("bare", false):
			continue
		var kind: String = op.get("kind", "door")
		var win := kind == "window"
		var sill: float = op.get("sill", 0.95 if win else 0.0)
		var head: float = op.get("head", 2.1 if win else (2.3 if kind == "arch" else 2.05))
		var d := 0.046 if win else 0.03            # proud of the frame: a window's frame stands out further than a door's
		var lo := sill - FRAME if sill > 0.0 else 0.0
		var hi := head + FRAME
		var l0 := maxf(a - FRAME - SURROUND, from)
		var r1 := minf(e + FRAME + SURROUND, to)
		if a - FRAME - l0 > 0.03:
			_out(p, n, along_u, plane, face, l0, a - FRAME, lo, hi, d, look, 0.002)
		if r1 - e - FRAME > 0.03:
			_out(p, n, along_u, plane, face, e + FRAME, r1, lo, hi, d, look, 0.002)
		_out(p, n, along_u, plane, face, l0, r1, hi, hi + SURROUND, d, look, 0.002)
		if sill > 0.0:
			var ledge: Variant = stool if stool != null else look
			_out(p, n, along_u, plane, face, maxf(l0 - 0.03, from), minf(r1 + 0.03, to), lo - 0.05, lo, 0.085, ledge, 0.003)
			if lo - 0.2 > 0.05:     # its top tucked up into the sill board
				_out(p, n, along_u, plane, face, a - FRAME, e + FRAME, lo - 0.2, lo - 0.045, d, look, 0.004)


## Dress the walls round a room at once: its back wall (at v0), its left wall
## (at u0) and its right wall (at u1), each from corner to corner. back, left
## and right are the openings each wall was built with, or null to leave it.
static func room_walls(p: Node3D, b: Variant, u0: float, v0: float, u1: float, v1: float, style: Dictionary, back: Variant = [], left: Variant = [], right: Variant = []) -> void:
	var i := T * 0.5
	if back != null:
		dress(p, b, true, v0, 1.0, u0 + i, u1 - i, back, style)
	if left != null:
		dress(p, b, false, u0, 1.0, v0 + i, v1 - i, left, style)
	if right != null:
		dress(p, b, false, u1, -1.0, v0 + i, v1 - i, right, style)


# ------------------------------------------------------------------- floors

## A border of another floor round a room, `w` wide, just inside its walls
## (u0, v0, u1, v1 are the walls' middle lines, as for p.room). People walk on it.
static func border(p: Node3D, b: Variant, u0: float, v0: float, u1: float, v1: float, look: Variant, w := 0.3) -> void:
	var n := _node(p, b)
	var i := T * 0.5 + 0.01      # a little off the walls' faces (its edge under the skirting)
	var y := 0.003
	var th := 0.006
	Kit.box(n, Vector3(u1 - u0 - 2.0 * i, th, w), p.pt((u0 + u1) * 0.5, v0 + i + w * 0.5, y), look)
	Kit.box(n, Vector3(u1 - u0 - 2.0 * i, th, w), p.pt((u0 + u1) * 0.5, v1 - i - w * 0.5, y), look)
	Kit.box(n, Vector3(w, th, v1 - v0 - 2.0 * i - 2.0 * w), p.pt(u0 + i + w * 0.5, (v0 + v1) * 0.5, y), look)
	Kit.box(n, Vector3(w, th, v1 - v0 - 2.0 * i - 2.0 * w), p.pt(u1 - i - w * 0.5, (v0 + v1) * 0.5, y), look)


## A mat, a runner or a patch of another floor: (u, v) its middle, w across and
## d deep. `edge`, if given, is the colour of a binding round it. People walk on it.
static func mat(p: Node3D, b: Variant, u: float, v: float, w: float, d: float, look: Variant, edge: Variant = null) -> Node3D:
	var g := Kit.group(_node(p, b), p.pt(u, v))
	if edge != null:
		Kit.box(g, Vector3(w, 0.008, d), Vector3(0, 0.004, 0), edge)
		Kit.box(g, Vector3(w - 0.12, 0.008, d - 0.12), Vector3(0, 0.0065, 0), look)
	else:
		Kit.box(g, Vector3(w, 0.009, d), Vector3(0, 0.0045, 0), look)
	return g


## Painted stripes on a floor (a loading bay's hatching, a line to stand
## behind): n bars of `look`, w by d, `gap` apart along u, the first at (u, v),
## each turned `slant` degrees.
static func hatch(p: Node3D, b: Variant, u: float, v: float, n: int, w: float, d: float, gap: float, look: Variant, slant := 0.0) -> void:
	var g := Kit.group(_node(p, b), p.pt(u, v))
	for i in n:
		Kit.box(g, Vector3(w, 0.006, d), Vector3(i * (w + gap), 0.004, 0), look, Vector3(0, slant, 0))


# ------------------------------------------------------------------- lights

## A fluorescent fitting on a wall's face, high up: a steel trough with a
## glowing diffuser along it, `w` long, its middle at height y.
static func wall_strip(p: Node3D, b: Variant, u: float, v: float, yaw := 0.0, w := 1.2, y := 2.5, glow := TUBE) -> Node3D:
	var g := Kit.group(_node(p, b), p.pt(u, v), Vector3(0, yaw, 0))
	Kit.box(g, Vector3(w, 0.12, 0.09), Vector3(0, y, 0.045), Color(0.88, 0.88, 0.84))
	Kit.box(g, Vector3(w - 0.06, 0.07, 0.03), Vector3(0, y - 0.02, 0.1), Kit.flat(glow, 1.5))
	for x: float in [-w * 0.5 + 0.03, w * 0.5 - 0.03]:      # the end caps: their backs sunk a little, off the trough's
		Kit.box(g, Vector3(0.05, 0.13, 0.1335), Vector3(x, y - 0.01, 0.06325), Color(0.8, 0.8, 0.76))
	return g


## A fluorescent fitting hung from the ceiling on two rods: a steel trough with
## a glowing diffuser under it, `w` long, along `yaw`, its underside at `y`. The
## rods stop at the tops of the walls (`ceil`).
static func strip_light(p: Node3D, b: Variant, u: float, v: float, yaw := 0.0, w := 1.3, y := 2.5, glow := TUBE, ceil := 2.9) -> Node3D:
	var g := Kit.group(_node(p, b), p.pt(u, v), Vector3(0, yaw, 0))
	Kit.box(g, Vector3(w, 0.07, 0.24), Vector3(0, y + 0.075, 0), Color(0.88, 0.88, 0.84))
	Kit.box(g, Vector3(w - 0.06, 0.04, 0.17), Vector3(0, y + 0.02, 0), Kit.flat(glow, 1.5))
	var rod := ceil - y - 0.11
	if rod > 0.02:
		for x: float in [-w * 0.32, w * 0.32]:
			Kit.cyl(g, 0.008, rod, Vector3(x, y + 0.11 + rod * 0.5, 0), Props.IRON, Vector3.ZERO, 4)
	return g


## A lamp hanging on a flex from the ceiling (`ceil`): kind "cone" (a metal
## shade: kitchens, stores), "drum" (a fabric shade: homes), "bulb" (a bare bulb
## on its wire: a cell, an interview room) or "globe" (a milk-glass globe:
## halls). Its bottom at y. The lamp glows; `light` above 0 also lights the room.
static func pendant(p: Node3D, b: Variant, u: float, v: float, y := 2.2, shade := Color(0.86, 0.2, 0.16), kind := "cone", glow := WARM, light := 0.0, ceil := 2.9) -> Node3D:
	var g := Kit.group(_node(p, b), p.pt(u, v))
	var top := y
	match kind:
		"drum":
			Kit.cyl(g, 0.26, 0.24, Vector3(0, y + 0.12, 0), shade, Vector3.ZERO, 14, 0.22)
			Kit.cyl(g, 0.21, 0.01, Vector3(0, y + 0.02, 0), Kit.flat(glow, 1.3), Vector3.ZERO, 14)
			top = y + 0.24
		"bulb":
			Kit.ball(g, 0.06, Vector3(0, y + 0.06, 0), Kit.flat(glow, 2.4), 8)
			Kit.cyl(g, 0.032, 0.07, Vector3(0, y + 0.14, 0), Props.STEEL, Vector3.ZERO, 6)
			top = y + 0.175
		"globe":
			Kit.ball(g, 0.16, Vector3(0, y + 0.16, 0), Kit.flat(Color(1.0, 0.97, 0.9), 1.1), 12)
			Kit.cyl(g, 0.06, 0.06, Vector3(0, y + 0.33, 0), BRASS, Vector3.ZERO, 8)
			top = y + 0.36
		_:
			Kit.cyl(g, 0.3, 0.2, Vector3(0, y + 0.1, 0), shade, Vector3.ZERO, 14, 0.06)
			Kit.cyl(g, 0.25, 0.01, Vector3(0, y + 0.01, 0), Kit.flat(glow, 1.6), Vector3.ZERO, 14)
			Kit.cyl(g, 0.05, 0.05, Vector3(0, y + 0.22, 0), shade.darkened(0.3), Vector3.ZERO, 8)
			top = y + 0.245
	if ceil - top > 0.02:
		Kit.cyl(g, 0.007, ceil - top, Vector3(0, (ceil + top) * 0.5, 0), Props.DARK, Vector3.ZERO, 4)
		Kit.cyl(g, 0.06, 0.03, Vector3(0, ceil - 0.015, 0), Props.DARK, Vector3.ZERO, 8)
	if light > 0.0:
		Kit.omni(g, Vector3(0, y - 0.2, 0), glow, light, 4.5)
	return g


## A light on a wall's face: kind "cage" (a bulkhead lamp in a wire cage:
## cells, yards, loading bays), "shade" (a little fabric shade on a brass arm:
## homes), "globe" (a glass globe on an iron bracket), "exit" (a lit EXIT box
## over a door). Its middle at height y.
static func sconce(p: Node3D, b: Variant, u: float, v: float, yaw := 0.0, kind := "cage", y := 2.1, glow := WARM, light := 0.0) -> Node3D:
	var g := Kit.group(_node(p, b), p.pt(u, v), Vector3(0, yaw, 0))
	match kind:
		"shade":
			Kit.box(g, Vector3(0.09, 0.15, 0.02), Vector3(0, y - 0.14, 0.01), BRASS)
			Kit.box(g, Vector3(0.025, 0.025, 0.15), Vector3(0, y - 0.12, 0.09), BRASS)
			Kit.cyl(g, 0.13, 0.18, Vector3(0, y, 0.18), Color(0.98, 0.9, 0.7), Vector3.ZERO, 10, 0.09)
			Kit.cyl(g, 0.1, 0.01, Vector3(0, y - 0.092, 0.18), Kit.flat(glow, 1.4), Vector3.ZERO, 10)
		"globe":       # the plate and the arm under the globe, where they show from in front of it
			Kit.box(g, Vector3(0.09, 0.2, 0.025), Vector3(0, y - 0.14, 0.0125), Props.IRON)
			Kit.tube(g, Vector3(0, y - 0.2, 0.02), Vector3(0, y - 0.2, 0.11), 0.012, Props.IRON, 5)
			Kit.tube(g, Vector3(0, y - 0.2, 0.11), Vector3(0, y - 0.125, 0.19), 0.012, Props.IRON, 5)
			Kit.cyl(g, 0.035, 0.05, Vector3(0, y - 0.105, 0.2), BRASS, Vector3.ZERO, 10, 0.065)      # the gallery it sits in
			Kit.ball(g, 0.1, Vector3(0, y, 0.2), Kit.flat(glow, 1.0), 10)
		"exit":
			Kit.box(g, Vector3(0.5, 0.2, 0.08), Vector3(0, y, 0.04), Color(0.9, 0.9, 0.86))
			Kit.box(g, Vector3(0.44, 0.15, 0.01), Vector3(0, y, 0.083), Kit.flat(Color(0.85, 0.12, 0.1), 1.2))
			Props.words(g, "EXIT", Vector3(0, y, 0.093), 0.11, Color(1.0, 0.95, 0.9))
		_:             # round, so it reads as a lamp and not a grille: a base, a glowing dome, a rim and a cross of bars
			Kit.disc(g, 0.13, Vector3(0, y, 0.015), Props.IRON, 0.03, 14)
			var dome := Kit.ball(g, 0.095, Vector3(0, y, 0.03), Kit.flat(glow, 1.3), 12)
			dome.scale = Vector3(1.0, 1.0, 0.75)
			Kit.ring(g, 0.118, 0.022, Vector3(0, y, 0.04), Props.IRON)
			for s: float in [-1.0, 1.0]:      # the bars' legs, from the rim out to the cross
				Kit.tube(g, Vector3(s * 0.1, 0, 0.04) + Vector3(0, y, 0), Vector3(s * 0.1, 0, 0.1) + Vector3(0, y, 0), 0.008, Props.IRON, 4)
				Kit.tube(g, Vector3(0, y + s * 0.1, 0.04), Vector3(0, y + s * 0.1, 0.1), 0.008, Props.IRON, 4)
			Kit.box(g, Vector3(0.21, 0.016, 0.016), Vector3(0, y, 0.105), Props.IRON)
			Kit.box(g, Vector3(0.016, 0.21, 0.016), Vector3(0, y, 0.105), Props.IRON)
	if light > 0.0:
		Kit.omni(g, Vector3(0, y - 0.1, 0.5), glow, light, 3.5)
	return g


## A chandelier hanging from the ceiling (`ceil`) on a brass stem: a bowl with
## a finial under it, and a ring of `arms` curving up and out from it, each with
## a candle bulb in a drip pan, crystal drops hanging between them. Its lowest
## point at y, its arms reaching r. `light` above 0 also lights the room.
static func chandelier(p: Node3D, b: Variant, u: float, v: float, y := 2.2, r := 0.42, arms := 6, look := BRASS, glow := WARM, light := 0.0, ceil := 2.9) -> Node3D:
	var g := Kit.group(_node(p, b), p.pt(u, v))
	var hub := y + 0.12
	var stem := ceil - hub - 0.1
	Kit.ball(g, 0.055, Vector3(0, y + 0.055, 0), look, 10)                                    # the finial
	Kit.cyl(g, 0.11, 0.1, Vector3(0, hub + 0.05, 0), look, Vector3.ZERO, 12, 0.05)            # the bowl
	Kit.cyl(g, 0.018, stem, Vector3(0, hub + 0.1 + stem * 0.5, 0), look, Vector3.ZERO, 6)     # the stem
	Kit.ball(g, 0.045, Vector3(0, hub + 0.1 + stem * 0.35, 0), look, 8)                       # a knop on it
	Kit.cyl(g, 0.09, 0.03, Vector3(0, ceil - 0.015, 0), look, Vector3.ZERO, 12)               # the ceiling rose
	var flame := Kit.flat(glow, 2.2)
	var crystal := Color(0.88, 0.95, 1.0)
	Kit.ring(g, r * 0.72 + 0.006, 0.01, Vector3(0, hub + 0.07, 0), look, Vector3(-90, 0, 0))     # the ring the drops hang from
	for i in arms:
		var a := TAU * float(i) / arms
		var out := Vector3(cos(a), 0, sin(a))
		var elbow := out * r * 0.55 + Vector3(0, hub + 0.02, 0)
		var tip := out * r + Vector3(0, hub + 0.12, 0)
		Kit.tube(g, Vector3(0, hub + 0.07, 0), elbow, 0.012, look, 5)
		Kit.tube(g, elbow, tip, 0.012, look, 5)
		Kit.cyl(g, 0.04, 0.02, tip + Vector3(0, 0.01, 0), look, Vector3.ZERO, 8)                      # the drip pan
		Kit.cyl(g, 0.016, 0.09, tip + Vector3(0, 0.065, 0), Color(0.97, 0.95, 0.88), Vector3.ZERO, 6)  # the candle
		Kit.ball(g, 0.026, tip + Vector3(0, 0.13, 0), flame, 6)                                         # its bulb
		var drop := out.rotated(Vector3.UP, PI / arms) * r * 0.72 + Vector3(0, hub - 0.03, 0)
		Kit.tube(g, drop + Vector3(0, 0.1, 0), drop + Vector3(0, 0.03, 0), 0.004, crystal, 4)
		Kit.ball(g, 0.024, drop, crystal, 6)
	if light > 0.0:
		Kit.omni(g, Vector3(0, y - 0.1, 0), glow, light, 5.0)
	return g


# ------------------------------------------------------------- on the walls

## A low mound of stacked strips: a hill in a picture (`r` half as wide as it
## is at the bottom, `hh` high), cut off at the picture's edges.
static func _mound(pic: Node3D, x0: float, y0: float, r: float, hh: float, look: Color, z: float, half_w: float) -> void:
	var steps := 4
	for k in steps:
		var f := float(k) / steps
		var half := r * sqrt(1.0 - f * f)
		var a := maxf(x0 - half, -half_w)
		var e := minf(x0 + half, half_w)
		if e - a < 0.01:
			continue
		Kit.box(pic, Vector3(e - a, hh / steps, 0.004), Vector3((a + e) * 0.5, y0 + hh * (k + 0.5) / steps, z), look)


## A framed picture on a wall's face: a moulded frame, a mount, and a flat
## picture in a few bold shapes. kind: "hills", "sea", "city", "flowers",
## "face", "certificate", "shapes", "map", "mountain". Its middle at height y.
static func picture(p: Node3D, b: Variant, u: float, v: float, yaw := 0.0, w := 0.8, h := 0.6, kind := "hills", frame := Color(0.78, 0.6, 0.22), y := 1.6, mount := Color(0.95, 0.92, 0.84)) -> Node3D:
	var g := Kit.group(_node(p, b), p.pt(u, v), Vector3(0, yaw, 0))
	Kit.box(g, Vector3(w, h, 0.035), Vector3(0, y, 0.0175), frame)
	Kit.box(g, Vector3(w - 0.07, h - 0.07, 0.01), Vector3(0, y, 0.04), frame.darkened(0.3))
	Kit.box(g, Vector3(w - 0.1, h - 0.1, 0.01), Vector3(0, y, 0.044), mount)
	var pw := w - 0.2
	var ph := h - 0.2
	var pic := Kit.group(g, Vector3(0, y, 0.05))
	match kind:
		"sea":
			Kit.box(pic, Vector3(pw, ph, 0.004), Vector3.ZERO, Color(0.55, 0.8, 0.95))
			Kit.box(pic, Vector3(pw, ph * 0.42, 0.004), Vector3(0, -ph * 0.29, 0.002), Color(0.15, 0.38, 0.7))
			Kit.disc(pic, ph * 0.13, Vector3(pw * 0.28, ph * 0.22, 0.004), Color(1.0, 0.85, 0.25), 0.004, 10)
			Kit.box(pic, Vector3(pw * 0.26, ph * 0.08, 0.004), Vector3(-pw * 0.12, -ph * 0.1, 0.006), Color(0.8, 0.18, 0.14))
			Kit.box(pic, Vector3(pw * 0.14, ph * 0.3, 0.004), Vector3(-pw * 0.12, ph * 0.1, 0.006), Color(0.98, 0.97, 0.92), Vector3(0, 0, -8))
		"city":
			Kit.box(pic, Vector3(pw, ph, 0.004), Vector3.ZERO, Color(0.12, 0.12, 0.3))
			Kit.disc(pic, ph * 0.11, Vector3(-pw * 0.3, ph * 0.26, 0.002), Color(0.98, 0.95, 0.75), 0.004, 10)
			for i in 6:
				var bw := pw / 6.0
				var bh := ph * (0.3 + 0.45 * Props.rnd(i * 2.3 + w))
				var x := -pw * 0.5 + (i + 0.5) * bw
				Kit.box(pic, Vector3(bw - 0.006, bh, 0.004), Vector3(x, -ph * 0.5 + bh * 0.5, 0.004), Color(0.3, 0.2, 0.42).darkened(0.2 * (i % 2)))
				Kit.box(pic, Vector3(bw * 0.3, bh * 0.12, 0.004), Vector3(x, -ph * 0.5 + bh * 0.62, 0.006), Color(1.0, 0.85, 0.35))
		"flowers":
			Kit.box(pic, Vector3(pw, ph, 0.004), Vector3.ZERO, Color(0.96, 0.86, 0.6))
			Kit.box(pic, Vector3(pw * 0.22, ph * 0.3, 0.004), Vector3(0, -ph * 0.32, 0.004), Color(0.2, 0.42, 0.75))
			for i in 3:
				var x := (i - 1) * pw * 0.2
				Kit.box(pic, Vector3(0.012, ph * 0.36, 0.004), Vector3(x * 0.6, -ph * 0.03, 0.003), Color(0.2, 0.5, 0.25), Vector3(0, 0, -x * 60.0))
				var fy := ph * 0.2 + 0.03 * (i % 2)
				Kit.disc(pic, ph * 0.12, Vector3(x, fy, 0.006), [Color(0.9, 0.2, 0.25), Color(1.0, 0.75, 0.15), Color(0.85, 0.35, 0.65)][i], 0.004, 10)
				Kit.disc(pic, ph * 0.04, Vector3(x, fy, 0.008), Color(1.0, 0.95, 0.6), 0.004, 8)
		"face":
			Kit.box(pic, Vector3(pw, ph, 0.004), Vector3.ZERO, Color(0.25, 0.3, 0.38))
			Kit.box(pic, Vector3(pw * 0.7, ph * 0.3, 0.004), Vector3(0, -ph * 0.35, 0.004), Color(0.12, 0.12, 0.16))
			var head := Kit.disc(pic, ph * 0.22, Vector3(0, ph * 0.05, 0.006), Color(0.86, 0.66, 0.5), 0.004, 12)
			head.scale = Vector3(0.85, 1.0, 1.2)
			Kit.box(pic, Vector3(pw * 0.3, ph * 0.08, 0.004), Vector3(0, ph * 0.26, 0.008), Color(0.55, 0.55, 0.58))
		"certificate":
			Kit.box(pic, Vector3(pw, ph, 0.004), Vector3.ZERO, Color(0.98, 0.95, 0.85))
			for k in 4:
				Kit.box(pic, Vector3(pw * (0.8 if k == 0 else 0.6), 0.03 if k == 0 else 0.012, 0.004), Vector3(0, ph * (0.3 - k * 0.15), 0.004), Color(0.3, 0.25, 0.2))
			Kit.disc(pic, ph * 0.12, Vector3(pw * 0.3, -ph * 0.3, 0.006), Color(0.8, 0.15, 0.12), 0.004, 10)
		"shapes":
			Kit.box(pic, Vector3(pw, ph, 0.004), Vector3.ZERO, Color(0.97, 0.95, 0.9))
			Kit.box(pic, Vector3(pw * 0.45, ph * 0.55, 0.004), Vector3(-pw * 0.22, ph * 0.18, 0.004), Color(0.86, 0.14, 0.12))
			Kit.box(pic, Vector3(pw * 0.3, ph * 0.35, 0.004), Vector3(pw * 0.3, -ph * 0.28, 0.004), Color(0.14, 0.3, 0.82))
			Kit.disc(pic, ph * 0.16, Vector3(pw * 0.2, ph * 0.2, 0.006), Color(0.98, 0.76, 0.1), 0.004, 12)
			Kit.box(pic, Vector3(pw, 0.02, 0.004), Vector3(0, -ph * 0.08, 0.008), Props.DARK)
		"map":
			Kit.box(pic, Vector3(pw, ph, 0.004), Vector3.ZERO, Color(0.92, 0.9, 0.8))
			for k in 5:
				Kit.box(pic, Vector3(pw, 0.012, 0.004), Vector3(0, -ph * 0.4 + k * ph * 0.2, 0.004), Color(0.75, 0.72, 0.62))
				Kit.box(pic, Vector3(0.012, ph, 0.004), Vector3(-pw * 0.4 + k * pw * 0.2, 0, 0.004), Color(0.75, 0.72, 0.62))
			Kit.box(pic, Vector3(pw * 0.35, ph * 0.25, 0.004), Vector3(pw * 0.15, ph * 0.12, 0.006), Color(0.55, 0.78, 0.5))
			Kit.box(pic, Vector3(pw * 0.96, 0.03, 0.004), Vector3(0, -ph * 0.12, 0.008), Color(0.9, 0.7, 0.25), Vector3(0, 0, 12))
			for k in 4:
				Kit.disc(pic, 0.022, Vector3(-pw * 0.3 + Props.rnd(k * 3.1 + u) * pw * 0.6, -ph * 0.35 + Props.rnd(k * 5.7 + v) * ph * 0.7, 0.01), Color(0.85, 0.12, 0.1), 0.004, 8)
		"mountain":
			Kit.box(pic, Vector3(pw, ph, 0.004), Vector3.ZERO, Color(0.98, 0.7, 0.45))
			Kit.disc(pic, ph * 0.13, Vector3(pw * 0.25, ph * 0.22, 0.002), Color(1.0, 0.95, 0.7), 0.004, 10)
			for k in 5:
				var half := pw * 0.42 * (1.0 - k / 5.0)
				Kit.box(pic, Vector3(half * 2.0, ph * 0.14, 0.004), Vector3(-pw * 0.06, -ph * 0.43 + k * ph * 0.14, 0.004), Color(0.35, 0.3, 0.55).lightened(0.05 * k))
			Kit.box(pic, Vector3(pw * 0.16, ph * 0.1, 0.004), Vector3(-pw * 0.06, -ph * 0.43 + 4.0 * ph * 0.14 + ph * 0.02, 0.006), Color(0.98, 0.97, 0.95))
		_:     # hills
			Kit.box(pic, Vector3(pw, ph, 0.004), Vector3.ZERO, Color(0.6, 0.82, 0.95))
			Kit.disc(pic, ph * 0.12, Vector3(pw * 0.28, ph * 0.24, 0.002), Color(1.0, 0.85, 0.25), 0.004, 10)
			_mound(pic, -pw * 0.2, -ph * 0.5, pw * 0.45, ph * 0.55, Color(0.3, 0.62, 0.3), 0.004, pw * 0.5)
			_mound(pic, pw * 0.3, -ph * 0.5, pw * 0.4, ph * 0.38, Color(0.22, 0.5, 0.25), 0.006, pw * 0.5)
	return g


## A lit display header on a wall's face (over a cigarette rack, a counter): a
## dark case `w` long and `h` high, its middle at height y, and across it a row
## of glowing panels, one for each colour in `panels`, each with a pale band.
static func lightbox(p: Node3D, b: Variant, u: float, v: float, yaw := 0.0, w := 2.0, h := 0.36, y := 2.15, panels := [], frame := Props.DARK) -> Node3D:
	var g := Kit.group(_node(p, b), p.pt(u, v), Vector3(0, yaw, 0))
	Kit.box(g, Vector3(w, h, 0.12), Vector3(0, y, 0.06), frame)
	var n := maxi(panels.size(), 1)
	var pw := (w - 0.06) / n
	var ph := h - 0.07
	for i in n:
		var c: Color = panels[i] if panels.size() > 0 else Color(0.95, 0.95, 0.9)
		var x := -w * 0.5 + 0.03 + pw * (i + 0.5)
		Kit.box(g, Vector3(pw - 0.03, ph, 0.01), Vector3(x, y, 0.125), Kit.flat(c, 0.8))
		Kit.box(g, Vector3(pw - 0.03, ph * 0.3, 0.004), Vector3(x, y - ph * 0.12, 0.132), Kit.flat(Color(1.0, 0.98, 0.92), 0.9))
	return g


## A cork pinboard on a wall's face in a wooden frame, its middle at height y,
## with paper notes pinned up on it every which way.
static func corkboard(p: Node3D, b: Variant, u: float, v: float, yaw := 0.0, w := 0.9, h := 0.6, y := 1.55, frame := Color(0.5, 0.34, 0.2)) -> Node3D:
	var g := Kit.group(_node(p, b), p.pt(u, v), Vector3(0, yaw, 0))
	Kit.box(g, Vector3(w - 0.08, h - 0.08, 0.032), Vector3(0, y, 0.016), Kit.tex("in_terrazzo", 0.35, Color(0.7, 0.52, 0.34), false, Color(0.86, 0.62, 0.4)))
	for s: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(w, 0.04, 0.05), Vector3(0, y + s * (h * 0.5 - 0.02), 0.025), frame)
		Kit.box(g, Vector3(0.04, h - 0.08, 0.05), Vector3(s * (w * 0.5 - 0.02), y, 0.025), frame)
	var key := u * 3.7 + v * 1.3
	var papers := [Color(0.98, 0.97, 0.92), Color(0.99, 0.93, 0.55), Color(0.98, 0.8, 0.82), Color(0.8, 0.9, 0.98), Color(0.92, 0.98, 0.8)]
	var pins := [Color(0.85, 0.15, 0.12), Color(0.15, 0.35, 0.8), Color(0.95, 0.75, 0.1)]
	var count := clampi(int(w * h * 12.0), 3, 8)
	var cols := ceili(count / 2.0)
	var inner_w := w - 0.08
	var inner_h := h - 0.08
	for i in count:
		var nw := minf(0.1 + 0.08 * Props.rnd(key + i * 2.1), inner_w / cols)
		var nh := minf(0.09 + 0.07 * Props.rnd(key + i * 3.3), inner_h * 0.48)
		var x := -inner_w * 0.5 + inner_w * ((i % cols) + 0.5) / cols + (Props.rnd(key + i * 5.9) - 0.5) * 0.05
		x = clampf(x, -inner_w * 0.5 + nw * 0.5, inner_w * 0.5 - nw * 0.5)
		var yy := y + (0.25 if i < cols else -0.25) * inner_h + (Props.rnd(key + i * 7.1) - 0.5) * 0.03
		var z := 0.034 + 0.0015 * i
		var note := Kit.group(g, Vector3(x, yy, z), Vector3(0, 0, (Props.rnd(key + i * 4.3) - 0.5) * 16.0))
		Kit.box(note, Vector3(nw, nh, 0.002), Vector3.ZERO, papers[absi(i + int(key)) % papers.size()])
		for k in 2:
			Kit.box(note, Vector3(nw * (0.7 - 0.25 * k), 0.008, 0.001), Vector3(-nw * 0.05, nh * (0.1 - 0.22 * k), 0.0015), Color(0.35, 0.35, 0.42))
		Kit.ball(note, 0.011, Vector3(0, nh * 0.5 - 0.02, 0.008), pins[i % pins.size()], 6)
	return g


## A pegboard on a wall's face, w by h, its middle at height y, in a thin frame,
## hung with `kind`: "snacks" (bags of chips on hooks, in rows) or "tools" (a
## hammer, a saw, a spanner, a coil of cord).
static func pegboard(p: Node3D, b: Variant, u: float, v: float, yaw := 0.0, w := 1.0, h := 0.7, y := 1.55, kind := "snacks", frame := Color(0.55, 0.42, 0.28)) -> Node3D:
	var g := Kit.group(_node(p, b), p.pt(u, v), Vector3(0, yaw, 0))
	Kit.box(g, Vector3(w - 0.06, h - 0.06, 0.02), Vector3(0, y, 0.01), Kit.tex("in_pegboard", 0.4, Color(0.8, 0.7, 0.56), false, Color(0.9, 0.76, 0.56)))
	for s: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(w, 0.03, 0.03), Vector3(0, y + s * (h * 0.5 - 0.015), 0.015), frame)
		Kit.box(g, Vector3(0.03, h - 0.06, 0.03), Vector3(s * (w * 0.5 - 0.015), y, 0.015), frame)
	var key := u * 2.9 + v * 1.7
	if kind == "tools":
		var wood := Color(0.62, 0.42, 0.24)
		var x := -w * 0.5 + 0.14
		var hammer := Kit.group(g, Vector3(x, y, 0.035), Vector3(0, 0, 8))
		Kit.box(hammer, Vector3(0.03, 0.3, 0.025), Vector3(0, -0.04, 0), wood)
		Kit.box(hammer, Vector3(0.14, 0.045, 0.035), Vector3(0, 0.12, 0.004), Props.IRON)
		if w > 0.6:
			var saw := Kit.group(g, Vector3(x + 0.3, y + 0.05, 0.03), Vector3(0, 0, -4))
			Kit.box(saw, Vector3(0.36, 0.1, 0.004), Vector3(0.04, 0, 0), Props.STEEL)
			Kit.box(saw, Vector3(0.09, 0.11, 0.025), Vector3(-0.17, 0.005, 0.006), Color(0.8, 0.2, 0.14))
		if w > 0.9:
			Kit.box(Kit.group(g, Vector3(w * 0.5 - 0.3, y + 0.1, 0.03), Vector3(0, 0, 12)), Vector3(0.025, 0.24, 0.01), Vector3.ZERO, Props.STEEL)
		var coil := Kit.group(g, Vector3(w * 0.5 - 0.15, y - 0.1, 0.04))
		Kit.cyl(coil, 0.1, 0.04, Vector3.ZERO, Color(0.95, 0.55, 0.12), Vector3(90, 0, 0), 12)
		Kit.cyl(coil, 0.055, 0.05, Vector3.ZERO, Color(0.55, 0.3, 0.08), Vector3(90, 0, 0), 10)
	else:
		var bags := [Color(0.9, 0.18, 0.15), Color(0.98, 0.78, 0.12), Color(0.15, 0.4, 0.82), Color(0.2, 0.62, 0.3), Color(0.95, 0.5, 0.12), Color(0.55, 0.25, 0.65)]
		var cols := maxi(int((w - 0.08) / 0.17), 1)
		var rows := maxi(int((h - 0.08) / 0.26), 1)
		for r in rows:
			for c in cols:
				var i := r * cols + c
				var x := -w * 0.5 + 0.04 + (w - 0.08) * (c + 0.5) / cols
				var yy := y + h * 0.5 - 0.06 - (r + 0.5) * (h - 0.1) / rows
				Kit.box(g, Vector3(0.012, 0.012, 0.06), Vector3(x, yy + 0.1, 0.05), Props.STEEL)           # the hook
				var bag := Kit.group(g, Vector3(x, yy, 0.05 + 0.003 * (i % 3)), Vector3(0, 0, (Props.rnd(key + i * 3.7) - 0.5) * 10.0))
				var col: Color = bags[int(Props.rnd(key + i * 1.9) * bags.size()) % bags.size()]
				Kit.box(bag, Vector3(0.14, 0.2, 0.035), Vector3.ZERO, col)
				Kit.box(bag, Vector3(0.15, 0.03, 0.028), Vector3(0, 0.095, 0), col.darkened(0.25))        # the crimped top, flared
				Kit.box(bag, Vector3(0.1, 0.06, 0.004), Vector3(0, -0.01, 0.019), Color(0.98, 0.95, 0.85))
	return g


## A round convex mirror high up in a corner, so the till can see down the
## aisles: a dark rim round a pale dome on a bracket, turned `yaw` and tipped
## down. (u, v) is the corner; its middle at height y.
static func mirror(p: Node3D, b: Variant, u: float, v: float, yaw := 45.0, r := 0.22, y := 2.4) -> Node3D:
	var g := Kit.group(_node(p, b), p.pt(u, v, y), Vector3(16, yaw, 0))
	Kit.box(g, Vector3(0.03, 0.03, 0.24), Vector3(0, 0, 0.12), Props.IRON)
	var dome := Kit.ball(g, r, Vector3(0, 0, 0.26), Color(0.74, 0.82, 0.88), 14)
	dome.scale = Vector3(1, 1, 0.35)
	Kit.cyl(g, r + 0.02, 0.03, Vector3(0, 0, 0.255), Props.DARK, Vector3(90, 0, 0), 16)
	Kit.box(g, Vector3(r * 0.5, 0.035, 0.01), Vector3(-r * 0.25, r * 0.35, 0.3), Color(0.97, 0.98, 1.0), Vector3(0, 0, 30))
	return g


## A fire extinguisher on a wall's face: a red bottle on a bracket, a steel
## valve and lever on top, a black hose down its side, a label. Its foot at y.
static func extinguisher(p: Node3D, b: Variant, u: float, v: float, yaw := 0.0, y := 0.8) -> Node3D:
	var g := Kit.group(_node(p, b), p.pt(u, v), Vector3(0, yaw, 0))
	var red := Color(0.86, 0.12, 0.1)
	Kit.box(g, Vector3(0.12, 0.08, 0.04), Vector3(0, y + 0.4, 0.02), Props.IRON)
	Kit.cyl(g, 0.085, 0.46, Vector3(0, y + 0.23, 0.11), red, Vector3.ZERO, 12)
	Kit.cyl(g, 0.06, 0.04, Vector3(0, y + 0.48, 0.11), red.darkened(0.2), Vector3.ZERO, 10)
	Kit.cyl(g, 0.02, 0.07, Vector3(0, y + 0.535, 0.11), Props.STEEL, Vector3.ZERO, 6)
	Kit.box(g, Vector3(0.15, 0.02, 0.03), Vector3(0.045, y + 0.575, 0.11), Props.STEEL, Vector3(0, 0, -10))
	Kit.tube(g, Vector3(0.03, y + 0.53, 0.13), Vector3(0.1, y + 0.2, 0.16), 0.012, Props.DARK, 4)
	Kit.box(g, Vector3(0.07, 0.12, 0.004), Vector3(0, y + 0.22, 0.196), Color(0.95, 0.93, 0.85))
	return g


## A security camera high on a wall: a plate, an arm, and a camera body under
## a hood, tipped down at the room, its red light on. Its arm at height y.
static func camera(p: Node3D, b: Variant, u: float, v: float, yaw := 0.0, y := 2.5) -> Node3D:
	var g := Kit.group(_node(p, b), p.pt(u, v, y), Vector3(0, yaw, 0))
	var white := Color(0.9, 0.9, 0.88)
	Kit.box(g, Vector3(0.08, 0.12, 0.02), Vector3(0, 0, 0.01), white)
	Kit.box(g, Vector3(0.03, 0.03, 0.16), Vector3(0, 0, 0.1), white)
	var body := Kit.group(g, Vector3(0, -0.02, 0.18), Vector3(25, 0, 0))
	Kit.box(body, Vector3(0.1, 0.09, 0.22), Vector3(0, 0, 0.08), white.lightened(0.05))
	Kit.box(body, Vector3(0.12, 0.015, 0.25), Vector3(0, 0.052, 0.09), white.darkened(0.08))
	Kit.cyl(body, 0.03, 0.02, Vector3(0, 0, 0.2), Props.DARK, Vector3(90, 0, 0), 10)
	Kit.ball(body, 0.01, Vector3(0.035, -0.03, 0.192), Kit.flat(Color(1.0, 0.15, 0.1), 2.0), 5)
	return g


## A sunburst mirror on a wall's face: a round glass in a gilt ring and gilt
## rays all round it, long ones tipped with a bead and short ones between. `r`
## is the glass's radius; the rays reach r + 0.24. Its middle at height y.
static func sunburst(p: Node3D, b: Variant, u: float, v: float, yaw := 0.0, r := 0.2, y := 1.7, look := Color(0.9, 0.72, 0.28)) -> Node3D:
	var g := Kit.group(_node(p, b), p.pt(u, v), Vector3(0, yaw, 0))
	var rays := 16
	for i in rays:
		var long := i % 2 == 0
		var reach := 0.22 if long else 0.13
		var ray := Kit.group(g, Vector3(0, y, 0.012), Vector3(0, 0, 360.0 * float(i) / rays + 11.25))   # turned off square, so none lies along the wall's axes
		Kit.box(ray, Vector3(0.024 if long else 0.016, reach, 0.012), Vector3(0, r + reach * 0.5, 0), look)
		if long:
			Kit.ball(ray, 0.022, Vector3(0, r + reach, 0), look, 6)
	Kit.disc(g, r + 0.045, Vector3(0, y, 0.018), look, 0.03, 20)                        # the ring
	Kit.disc(g, r + 0.012, Vector3(0, y, 0.026), look.darkened(0.2), 0.024, 20)
	Kit.disc(g, r, Vector3(0, y, 0.032), Color(0.74, 0.84, 0.9), 0.016, 20)            # the glass
	var gleam := Kit.group(g, Vector3(-r * 0.3, y + r * 0.32, 0.042), Vector3(0, 0, 35))
	Kit.box(gleam, Vector3(r * 0.55, 0.03, 0.002), Vector3.ZERO, Color(0.96, 0.98, 1.0))
	return g


## A telephone on a kitchen wall: a base with a dial, the handset hung on its
## side, and the curly cord hanging in a loop from the handset to the base.
## Its middle at height y.
static func wall_phone(p: Node3D, b: Variant, u: float, v: float, yaw := 0.0, y := 1.5, look := Color(0.92, 0.86, 0.66)) -> Node3D:
	var g := Kit.group(_node(p, b), p.pt(u, v), Vector3(0, yaw, 0))
	Kit.bevel(g, Vector3(0.17, 0.25, 0.07), Vector3(0, y, 0.035), look, 0.02)
	Kit.disc(g, 0.055, Vector3(0, y + 0.03, 0.074), look.darkened(0.14), 0.008, 14)       # the dial
	for k in 8:
		var a := TAU * (k + 1.5) / 11.0
		Kit.disc(g, 0.009, Vector3(cos(a) * 0.036, y + 0.03 + sin(a) * 0.036, 0.079), Color(0.98, 0.97, 0.94), 0.004, 6)
	Kit.disc(g, 0.018, Vector3(0, y + 0.03, 0.08), Color(0.98, 0.97, 0.94), 0.004, 8)
	var hs := Kit.group(g, Vector3(0.115, y + 0.01, 0.05))                                 # the handset
	Kit.bevel(hs, Vector3(0.05, 0.22, 0.045), Vector3.ZERO, look, 0.018)
	for s: float in [-1.0, 1.0]:
		Kit.bevel(hs, Vector3(0.075, 0.065, 0.07), Vector3(0, s * 0.105, 0.008), look, 0.025)
	var a0 := Vector3(0.115, y - 0.125, 0.05)
	var a1 := Vector3(0.0, y - 0.125, 0.05)
	var cord := look.darkened(0.08)
	var turns := 26
	for k in turns + 1:        # the curly cord: a loop of little coils
		var t := float(k) / turns
		var at := a0.lerp(a1, t) + Vector3(0, -0.38 * sin(t * PI), 0.004 * (k % 2))
		Kit.ring(g, 0.017, 0.006, at, cord)
	return g


## A panel of glass blocks set in a wall's face (a bathroom, a stair), glowing
## with the light behind it, in a stone frame. w by h (each a multiple of 0.4,
## so the blocks come out whole), its middle at height y.
static func glass_blocks(p: Node3D, b: Variant, u: float, v: float, yaw := 0.0, w := 0.4, h := 0.8, y := 1.8, glow := Color(0.62, 0.78, 0.9), frame := Color(0.94, 0.94, 0.92)) -> Node3D:
	var g := Kit.group(_node(p, b), p.pt(u, v), Vector3(0, yaw, 0))
	var m: StandardMaterial3D = Kit.tex("in_glassblock", 0.8, glow, false, glow).duplicate()
	m.emission_enabled = true          # a soft glow, patterned like the blocks so the grout stays darker
	m.emission = glow * 0.6
	m.emission_energy_multiplier = 0.45
	m.emission_texture = m.albedo_texture
	Kit.box(g, Vector3(w, h, 0.03), Vector3(0, y, 0.015), m)
	for s: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(w + 0.14, 0.07, 0.05), Vector3(0, y + s * (h * 0.5 + 0.035), 0.025), frame)
		Kit.box(g, Vector3(0.07, h, 0.046), Vector3(s * (w * 0.5 + 0.035), y, 0.023), frame)
	return g


## Quoins: dressed stones up the corner of a street front, long and short by
## turns, from y0 to y1. The front wall's middle line is at v, the corner at u,
## which is also where the side wall's street face is; `side` +1 if the corner
## is the front's right-hand end, -1 its left. `wrap` lays them round the side
## face too, short where the front's are long.
static func quoins(p: Node3D, n: Node3D, v: float, u: float, y0: float, y1: float, look: Variant = Color(0.86, 0.82, 0.72), side := 1.0, wrap := true, course := 0.3, long := 0.4, short := 0.24) -> void:
	var f := v + T * 0.5
	var proud := 0.03
	for k in int((y1 - y0) / course):
		var lo := y0 + k * course + 0.012
		var hi := y0 + (k + 1) * course - 0.012
		var on_front := long if k % 2 == 0 else short
		var on_side := short if k % 2 == 0 else long
		var a := u - on_front if side > 0.0 else u - (proud if wrap else 0.0)
		var e := u + (proud if wrap else 0.0) if side > 0.0 else u + on_front
		p.slab(n, true, f + (proud - 0.01) * 0.5, a, e, lo, hi, proud + 0.01, look)
		if wrap:
			p.slab(n, false, u + side * (proud - 0.01) * 0.5, f - on_side, f - 0.01, lo, hi, proud + 0.01, look)


## Curtains each side of a window in a wall (on its `face` side), hanging in
## folds, tied back, with a pelmet box over them. a..e and sill..head as the
## opening. `long` runs them to the floor.
static func curtains(p: Node3D, b: Variant, along_u: bool, at: float, face: float, a: float, e: float, sill: float, head: float, cloth: Color, pelmet: Variant = null, long := false) -> void:
	var n := _node(p, b)
	var plane := at + face * T * 0.5
	var top := head + FRAME + 0.16
	var bottom := 0.06 if long else sill - FRAME - 0.12
	for side in 2:
		var x0 := a - FRAME - 0.3 if side == 0 else e + FRAME - 0.08
		var x1 := a - FRAME + 0.08 if side == 0 else e + FRAME + 0.3
		var k := 4
		for i in k:
			var s0 := x0 + (x1 - x0) * float(i) / k
			var s1 := x0 + (x1 - x0) * float(i + 1) / k
			_out(p, n, along_u, plane, face, s0, s1, bottom, top - 0.02, 0.07 + (0.03 if i % 2 == 0 else 0.0), cloth.darkened(0.14 * (i % 2)), 0.005)
		var tie := (sill + head) * 0.5 - 0.18
		_out(p, n, along_u, plane, face, x0 + 0.02, x1 - 0.02, tie, tie + 0.04, 0.115, cloth.lightened(0.3), 0.006)
	var pel: Variant = pelmet if pelmet != null else cloth.darkened(0.25)
	_out(p, n, along_u, plane, face, a - FRAME - 0.36, e + FRAME + 0.36, top - 0.04, top + 0.16, 0.15, pel, 0.007)


## What shows through a window in an outside wall: a backdrop just beyond it.
## kind "brick" (the wall across an alley, a lit window in it), "sky" (night
## over the roofs), "lot" (a back lot: a fence and a lamp's glow). `face` is the
## OUTSIDE side of the wall.
static func night_view(p: Node3D, b: Variant, along_u: bool, at: float, face: float, a: float, e: float, sill: float, head: float, kind := "brick") -> void:
	var n := _node(p, b)
	var plane := at + face * (T * 0.5 + 0.9)
	var w0 := a - 0.6
	var w1 := e + 0.6
	var y0 := sill - 0.5
	var y1 := head + 0.5
	var mid := (a + e) * 0.5
	match kind:
		"sky":
			p.slab(n, along_u, plane, w0, w1, y0, y1, 0.05, Color(0.16, 0.16, 0.36))
			p.slab(n, along_u, plane - face * 0.04, w0, w1, y0, sill + (head - sill) * 0.35, 0.02, Color(0.08, 0.07, 0.14))
			p.slab(n, along_u, plane - face * 0.07, mid - 0.1, mid + 0.25, y0, sill + (head - sill) * 0.55, 0.02, Color(0.06, 0.05, 0.1))
			p.slab(n, along_u, plane - face * 0.1, mid + 0.3, mid + 0.4, sill + (head - sill) * 0.2, sill + (head - sill) * 0.3, 0.02, Kit.flat(Color(1.0, 0.9, 0.6), 1.2))
		"lot":
			p.slab(n, along_u, plane, w0, w1, y0, y1, 0.05, Color(0.12, 0.13, 0.26))
			p.slab(n, along_u, plane - face * 0.04, w0, w1, y0, sill + 0.4, 0.02, Color(0.3, 0.3, 0.32))
			p.slab(n, along_u, plane - face * 0.07, a + (e - a) * 0.25, a + (e - a) * 0.25 + 0.05, y0, head - 0.2, 0.02, Color(0.2, 0.24, 0.24))
			p.slab(n, along_u, plane - face * 0.1, a + (e - a) * 0.25 - 0.08, a + (e - a) * 0.25 + 0.13, head - 0.3, head - 0.2, 0.02, Kit.flat(Color(1.0, 0.85, 0.5), 1.6))
		_:
			p.slab(n, along_u, plane, w0, w1, y0, y1, 0.05, Kit.tex("brick", 1.5, Color(0.4, 0.22, 0.2), true, Color(0.45, 0.4, 0.5)))
			p.slab(n, along_u, plane - face * 0.04, mid - 0.25, mid + 0.25, sill + 0.1, sill + 0.75, 0.02, Kit.flat(Color(1.0, 0.84, 0.5), 0.9))
			p.slab(n, along_u, plane - face * 0.07, mid - 0.012, mid + 0.012, sill + 0.1, sill + 0.75, 0.02, Color(0.25, 0.2, 0.18))


# ----------------------------------------------------------- street fronts

## A window on a street front, on the street face of the front wall at v:
## Kit.window's glass, frame, sill and lintel, a keystone (unless `keystone` is
## false), and behind lit glass a blind or curtains. (u, y) is the middle of the
## bottom of the glass. extra: "ac" (an air conditioner in it), "box" (a window
## box of flowers), "boarded".
static func front_window(p: Node3D, n: Node3D, u: float, v: float, y: float, w := 1.1, h := 1.4, lit := false, frame := Color(0.92, 0.9, 0.84), stone: Variant = Color(0.86, 0.82, 0.72), extra := "", key := 0.0, keystone := true) -> Node3D:
	var f := v + T * 0.5
	var glass: Variant = Kit.flat(Color(1.0, 0.84, 0.52), 0.55) if lit else Color(0.18, 0.21, 0.32)
	var g := Kit.window(n, w, h, p.pt(u, f, y + h * 0.5), frame, glass, 2, stone)
	if extra == "boarded":
		Kit.box(g, Vector3(w + 0.04, h + 0.04, 0.03), Vector3(0, 0, 0.065), Color(0.62, 0.48, 0.3))
		for k in 3:
			Kit.box(g, Vector3(w + 0.04, 0.06, 0.02), Vector3(0, -h * 0.35 + k * h * 0.35, 0.09), Color(0.5, 0.38, 0.24))
	elif lit:
		if Props.rnd(key + u * 1.7) > 0.5:
			Kit.box(g, Vector3(w - 0.04, h * 0.42, 0.006), Vector3(0, h * 0.27, 0.024), Kit.flat(Color(0.96, 0.9, 0.72), 0.5))
		else:
			for s: float in [-1.0, 1.0]:
				Kit.box(g, Vector3(w * 0.22, h - 0.04, 0.006), Vector3(s * w * 0.38, 0, 0.024), Kit.flat(Color(0.86, 0.3, 0.28), 0.3))
	else:
		Kit.box(g, Vector3(w * 0.3, h * 0.7, 0.006), Vector3(-w * 0.22, h * 0.05, 0.024), Color(0.27, 0.31, 0.44))       # a gleam on the dark glass
	if stone is Color and keystone:
		var key_stone: Color = stone
		Kit.box(g, Vector3(0.16, 0.24, 0.12), Vector3(0, h * 0.5 + 0.15, 0.06), key_stone.darkened(0.08))           # the keystone
	if extra == "ac":
		var ax := minf(w * 0.2, w * 0.5 - 0.34)        # its sides and its bracket's kept off the glass's edge
		Kit.block(g, Vector3(0.6, 0.42, 0.5), Vector3(ax, -h * 0.5 + 0.02, 0.2), Color(0.86, 0.85, 0.8))
		for k in 5:
			Kit.box(g, Vector3(0.5, 0.025, 0.01), Vector3(ax, -h * 0.5 + 0.1 + k * 0.065, 0.455), Color(0.55, 0.56, 0.58))
		Kit.box(g, Vector3(0.64, 0.04, 0.42), Vector3(ax, -h * 0.5 - 0.035, 0.22), Props.IRON)      # its top under the frame's
	elif extra == "box":
		Kit.block(g, Vector3(w + 0.1, 0.2, 0.24), Vector3(0, -h * 0.5 - 0.36, 0.2), Color(0.62, 0.36, 0.22))
		for k in 6:
			var x := -w * 0.5 + 0.05 + k * (w / 5.0)
			Kit.ball(g, 0.08, Vector3(x, -h * 0.5 - 0.13, 0.2), Color(0.25, 0.55, 0.3), 6)
			Kit.ball(g, 0.045, Vector3(x + 0.03, -h * 0.5 - 0.07, 0.26), [Color(0.95, 0.25, 0.3), Color(1.0, 0.8, 0.2), Color(0.95, 0.5, 0.8)][k % 3], 6)
	return g


## A gooseneck lamp over a shop's name board: from a plate on the street face
## of the front wall at v, at (u, y), an arm up, out and over, and at its end a
## shade turned down and back at the board, lit under.
static func gooseneck(p: Node3D, n: Node3D, u: float, v: float, y: float, look := Color(0.16, 0.36, 0.28), reach := 0.5) -> Node3D:
	var g := Kit.group(n, p.pt(u, v + T * 0.5, y))
	Kit.box(g, Vector3(0.12, 0.12, 0.03), Vector3(0, 0, 0.015), look)
	var bend := Vector3(0, 0.16, reach * 0.55)
	var tip := Vector3(0, 0.1, reach)
	Kit.tube(g, Vector3(0, 0, 0.02), bend, 0.016, look, 6)
	Kit.tube(g, bend, tip, 0.016, look, 6)
	var shade := Kit.group(g, tip, Vector3(53, 0, 0))
	Kit.cyl(shade, 0.15, 0.13, Vector3(0, -0.065, 0), look, Vector3.ZERO, 12, 0.04)
	Kit.cyl(shade, 0.13, 0.01, Vector3(0, -0.126, 0), Kit.flat(WARM, 1.8), Vector3.ZERO, 12)
	return g


## A bracketed cornice along the top of a street front, as on a Baltimore
## rowhouse: a frieze board, scroll brackets, a row of dentils and a deep
## overhang. On the street face of the front wall at v, from u0 to u1, its top at y.
static func cornice(p: Node3D, n: Node3D, v: float, u0: float, u1: float, y: float, look := Color(0.3, 0.28, 0.27), trim := Color(0.86, 0.82, 0.72), deep := 0.42) -> void:
	var f := v + T * 0.5
	_out(p, n, true, f, 1.0, u0, u1, y - 0.62, y - 0.18, 0.07, look)                  # the frieze
	_out(p, n, true, f, 1.0, u0 - 0.06, u1 + 0.06, y - 0.18, y - 0.1, deep * 0.6, trim)
	_out(p, n, true, f, 1.0, u0 - 0.1, u1 + 0.1, y - 0.1, y - 0.03, deep, look)      # the overhang
	_out(p, n, true, f, 1.0, u0 - 0.12, u1 + 0.12, y - 0.03, y, deep + 0.03, trim)
	var count := maxi(int((u1 - u0) / 0.9), 1)
	for i in count + 1:
		var x := u0 + 0.08 + (u1 - u0 - 0.16) * float(i) / float(count)
		var g := Kit.group(n, p.pt(x, f))
		# Each piece a different width and its top buried in the next, so no two share a face.
		Kit.box(g, Vector3(0.12, 0.4, 0.14), Vector3(0, y - 0.4, 0.14), trim)      # the bracket's face
		Kit.box(g, Vector3(0.1, 0.105, deep * 0.6 - 0.02), Vector3(0, y - 0.2275, (deep * 0.6 - 0.02) * 0.5 + 0.005), trim.darkened(0.06))
		Kit.box(g, Vector3(0.09, 0.08, 0.06), Vector3(0, y - 0.62, 0.17), trim.darkened(0.15))
	var dents := int((u1 - u0 - 0.1) / 0.2)
	for i in dents:
		var x := u0 + 0.1 + i * 0.2
		_out(p, n, true, f + 0.07, 1.0, x, x + 0.09, y - 0.27, y - 0.19, 0.045, trim)


## A round column, its foot at `pos` in `parent`: a square plinth, a tapering
## shaft, a flared capital and a square abacus on top at `h`. Nothing reaches
## further than `r` from its middle (a column on a 2r x 2r floor space).
static func column(parent: Node3D, pos: Vector3, h: float, r := 0.1, look := Color(0.84, 0.82, 0.76), sides := 12) -> Node3D:
	var g := Kit.group(parent, pos)
	var shaft := h - 0.12 - 0.16
	Kit.box(g, Vector3(r * 2.0, 0.12, r * 2.0), Vector3(0, 0.06, 0), look.darkened(0.12))
	Kit.cyl(g, r * 0.9, 0.05, Vector3(0, 0.145, 0), look.darkened(0.05), Vector3.ZERO, sides)
	Kit.cyl(g, r * 0.8, shaft, Vector3(0, 0.12 + shaft * 0.5, 0), look, Vector3.ZERO, sides, r * 0.7)
	Kit.cyl(g, r * 0.7, 0.08, Vector3(0, h - 0.12, 0), look.darkened(0.05), Vector3.ZERO, sides, r * 0.98)
	Kit.box(g, Vector3(r * 2.0, 0.08, r * 2.0), Vector3(0, h - 0.04, 0), look.darkened(0.06))
	return g


## A classical pediment, facing +z in `parent`, its base's middle at `pos`: a
## cornice along the bottom, a triangle `w` wide and `h` high over it filled with
## the `tympanum`, and a raking cornice up each slope standing proud of it.
static func pediment(parent: Node3D, pos: Vector3, w: float, h: float, deep := 0.2, look := Color(0.84, 0.82, 0.76), tympanum: Variant = null) -> Node3D:
	var g := Kit.group(parent, pos)
	var fill: Variant = tympanum if tympanum != null else look.darkened(0.15)
	Kit.box(g, Vector3(w + 0.14, 0.1, deep + 0.06), Vector3(0, 0.05, 0.03), look)
	Kit.prism(g, Vector3(w, h, deep), Vector3(0, 0.1 + h * 0.5, 0), fill)
	var half := w * 0.5
	var slope := atan2(h, half)
	var long := sqrt(half * half + h * h) + 0.1
	for s: float in [-1.0, 1.0]:
		var mid := Vector3(s * half * 0.5, 0.1 + h * 0.5, 0.03) + Vector3(s * sin(slope), cos(slope), 0.0) * 0.05
		Kit.box(g, Vector3(long, 0.1, deep + 0.06), mid, look, Vector3(0, 0, -s * rad_to_deg(slope)))
	return g


## The scales of justice in gilt, flat against a wall facing +z in `parent`: a
## foot, a post, a beam across it and a pan hanging from each end on its cords.
## `s` tall, its foot's middle at `pos`.
static func scales(parent: Node3D, pos: Vector3, s := 0.5, look := Color(0.86, 0.7, 0.28)) -> Node3D:
	var g := Kit.group(parent, pos)
	var d := 0.014
	Kit.box(g, Vector3(s * 0.4, s * 0.07, d), Vector3(0, s * 0.035, d * 0.5), look)
	Kit.box(g, Vector3(s * 0.06, s * 0.78, d), Vector3(0, s * 0.45, d * 0.5), look)
	Kit.box(g, Vector3(s * 0.96, s * 0.05, d), Vector3(0, s * 0.8, d * 1.5), look)
	Kit.disc(g, s * 0.07, Vector3(0, s * 0.88, d * 1.5), look, d, 10)
	for side: float in [-1.0, 1.0]:
		var x := side * s * 0.44
		for k: float in [-1.0, 1.0]:
			Kit.tube(g, Vector3(x, s * 0.8, d * 1.5), Vector3(x + k * s * 0.14, s * 0.44, d * 1.5), 0.005, look, 4)
		Kit.box(g, Vector3(s * 0.34, s * 0.05, d), Vector3(x, s * 0.43, d * 1.5), look)
		Kit.box(g, Vector3(s * 0.22, s * 0.05, d), Vector3(x, s * 0.385, d * 1.5), look)
	return g


## A parapet along the top of a flat-roofed front: the wall carried up a little
## with a coping on top: at v, from u0 to u1, from y to y + h.
static func parapet(p: Node3D, n: Node3D, v: float, u0: float, u1: float, y: float, h := 0.6, look: Variant = Color(0.5, 0.26, 0.2), coping := Color(0.82, 0.8, 0.74)) -> void:
	p.slab(n, true, v, u0, u1, y, y + h, T, look)
	p.slab(n, true, v, u0 - 0.06, u1 + 0.06, y + h, y + h + 0.1, T + 0.12, coping)


## A water tank on legs on a roof, seen over the parapet: (u, v) its middle on
## the plan, y the roof.
static func water_tank(p: Node3D, n: Node3D, u: float, v: float, y: float, r := 0.9, h := 1.6) -> void:
	var g := Kit.group(n, p.pt(u, v, y))
	var wood := Color(0.55, 0.38, 0.26)
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		Kit.box(g, Vector3(0.08, 1.0, 0.08), Vector3(s.x * r * 0.6, 0.5, s.y * r * 0.6), Props.IRON)
	Kit.box(g, Vector3(r * 1.5, 0.06, r * 1.5), Vector3(0, 1.0, 0), Props.IRON)
	Kit.cyl(g, r, h, Vector3(0, 1.03 + h * 0.5, 0), wood, Vector3.ZERO, 12)
	for k in 3:
		Kit.cyl(g, r + 0.02, 0.05, Vector3(0, 1.2 + k * h * 0.33, 0), Props.IRON, Vector3.ZERO, 12)
	Kit.cyl(g, r + 0.1, 0.55, Vector3(0, 1.03 + h + 0.27, 0), wood.darkened(0.3), Vector3.ZERO, 12, 0.05)


## A radio mast on a roof: a lattice tower `h` tall at (u, v), y the roof, with
## a red light on top.
static func mast(p: Node3D, n: Node3D, u: float, v: float, y: float, h := 4.0) -> void:
	var g := Kit.group(n, p.pt(u, v, y))
	var w := 0.36
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		Kit.tube(g, Vector3(s.x * w, 0, s.y * w), Vector3(s.x * 0.06, h, s.y * 0.06), 0.02, Props.IRON, 4)
	var steps := int(h / 0.5)
	for k in steps:
		var f0 := float(k) / steps
		var f1 := float(k + 1) / steps
		var w0 := lerpf(w, 0.06, f0)
		var w1 := lerpf(w, 0.06, f1)
		Kit.tube(g, Vector3(-w0, h * f0, w0), Vector3(w1, h * f1, w1), 0.01, Props.IRON, 4)
		Kit.tube(g, Vector3(w0, h * f0, w0), Vector3(w1, h * f1, -w1), 0.01, Props.IRON, 4)
	Kit.cyl(g, 0.012, 1.2, Vector3(0, h + 0.6, 0), Props.IRON, Vector3.ZERO, 4)
	Kit.ball(g, 0.06, Vector3(0, h + 1.22, 0), Kit.flat(Color(1.0, 0.2, 0.15), 2.0), 6)
	Kit.cyl(g, 0.22, 0.04, Vector3(0, h * 0.7, 0.0), Props.STEEL, Vector3(90, 0, 0), 10)


## A fire escape on a street front: a landing at each height in `levels`, a
## rail round it, a stair from each landing down to the one under it, and a
## ladder hanging from the lowest. On the face of the front wall at v, u0 to u1.
static func fire_escape(p: Node3D, n: Node3D, v: float, u0: float, u1: float, levels: Array, look := Color(0.14, 0.15, 0.17)) -> void:
	var f := v + T * 0.5
	var deep := 0.85
	var w := u1 - u0
	for i in levels.size():
		var y: float = levels[i]
		var g := Kit.group(n, p.pt((u0 + u1) * 0.5, f, y))
		Kit.box(g, Vector3(w, 0.05, deep), Vector3(0, 0, deep * 0.5), look)
		var slats := int(w / 0.12)
		for k in slats:
			Kit.box(g, Vector3(0.014, 0.012, deep - 0.04), Vector3(-w * 0.5 + 0.06 + k * 0.12, 0.031, deep * 0.5), look.lightened(0.18))
		Kit.box(g, Vector3(w, 0.04, 0.04), Vector3(0, 0.95, deep - 0.02), look)
		Kit.box(g, Vector3(w, 0.03, 0.03), Vector3(0, 0.5, deep - 0.02), look)
		for s: float in [-1.0, 1.0]:
			Kit.box(g, Vector3(0.04, 0.04, deep - 0.04), Vector3(s * (w * 0.5 - 0.02), 0.95, deep * 0.5 - 0.02), look)
			Kit.box(g, Vector3(0.03, 0.95, 0.03), Vector3(s * (w * 0.5 - 0.02), 0.475, deep - 0.02), look)
		var posts := int(w / 0.15)
		for k in range(1, posts):
			Kit.box(g, Vector3(0.016, 0.9, 0.016), Vector3(-w * 0.5 + w * float(k) / posts, 0.475, deep - 0.02), look)
		for k in 3:
			var x := -w * 0.35 + k * w * 0.35
			Kit.tube(g, Vector3(x, -0.02, deep - 0.05), Vector3(x, -0.45, 0.02), 0.02, look, 4)      # the braces under it
		var below: float = levels[i - 1] if i > 0 else y - 2.2
		if i > 0:
			var x0 := -w * 0.42
			var x1 := w * 0.22
			for z: float in [deep * 0.3, deep * 0.7]:
				Kit.tube(g, Vector3(x0, 0.02, z), Vector3(x1, below - y + 0.05, z), 0.02, look, 4)
			var treads := int((y - below) / 0.22)
			for k in range(1, treads):
				var f2 := float(k) / treads
				Kit.box(g, Vector3(0.12, 0.02, deep * 0.4), Vector3(lerpf(x0, x1, f2), lerpf(0.02, below - y + 0.05, f2), deep * 0.5), look.lightened(0.1))
		else:
			for z: float in [deep * 0.3, deep * 0.7]:
				Kit.box(g, Vector3(0.03, 1.4, 0.03), Vector3(w * 0.3, -0.7, z), look)
			for k in 5:
				Kit.box(g, Vector3(0.025, 0.025, deep * 0.4), Vector3(w * 0.3, -0.12 - k * 0.28, deep * 0.5), look)


## Neon tubing bent into a picture: a list of strokes, each a list of points
## (x, y in metres on the sign), lit in `colour`. Built facing +z at `pos`.
static func neon_shape(parent: Node3D, strokes: Array, pos: Vector3, colour: Color, yaw := 0.0, r := 0.016) -> Node3D:
	var g := Kit.group(parent, pos, Vector3(0, yaw, 0))
	var glow := Kit.flat(colour, 2.4)
	var halo := Kit.flat(Color(colour.r, colour.g, colour.b, 0.18))
	for stroke: Array in strokes:
		for i in stroke.size() - 1:
			var a: Vector2 = stroke[i]
			var b: Vector2 = stroke[i + 1]
			Kit.tube(g, Vector3(a.x, a.y, 0.03), Vector3(b.x, b.y, 0.03), r, glow, 6)
			Kit.tube(g, Vector3(a.x, a.y, 0.0), Vector3(b.x, b.y, 0.0), r * 3.2, halo, 6)
	return g


## A stoop: `steps` marble steps up to a front door, the top one `w` wide at
## the wall, each `tread` deep, stepping down towards the street, built in n.
## `cheeks` adds a low wall each side.
static func stoop(p: Node3D, n: Node3D, u: float, v: float, w := 1.3, steps := 3, rise := 0.1, tread := 0.26, look := Color(0.94, 0.94, 0.92), cheeks := false) -> void:
	var f := v + T * 0.5
	for k in steps:
		var hgt := rise * float(steps - k)
		Kit.block(n, Vector3(w, hgt - 0.025, tread), p.pt(u, f + tread * (k + 0.5)), look.darkened(0.035 * k))
		Kit.block(n, Vector3(w + 0.03, 0.025, tread + 0.02), p.pt(u, f + tread * (k + 0.5) + 0.01, hgt - 0.025), look.lightened(0.05))
	if cheeks:
		for s: float in [-1.0, 1.0]:
			Kit.block(n, Vector3(0.12, rise * steps + 0.18, tread * steps), p.pt(u + s * (w * 0.5 + 0.075), f + tread * steps * 0.5), look.darkened(0.1))


## A shopfront on the street face of a front wall at v, from u0 to u1: a
## pilaster at each end with a capital and a plinth, a fascia board for the
## shop's name from y0 to y1 with a moulded cornice on it, and under each window
## in `windows` (a list of [a, b, sill]) a stall riser faced in `riser`, with a
## sill on it.
static func shopfront(p: Node3D, n: Node3D, v: float, u0: float, u1: float, y0: float, y1: float, fascia: Variant, trim: Color, riser: Variant, windows := [], pilaster: Variant = null) -> void:
	var f := v + T * 0.5
	var pil: Variant = pilaster if pilaster != null else trim
	if fascia != null:
		_out(p, n, true, f, 1.0, u0, u1, y0, y1, 0.07, fascia)
	_out(p, n, true, f, 1.0, u0 - 0.04, u1 + 0.04, y1, y1 + 0.08, 0.13, trim)
	_out(p, n, true, f, 1.0, u0 - 0.08, u1 + 0.08, y1 + 0.08, y1 + 0.16, 0.18, trim.darkened(0.12))
	_out(p, n, true, f, 1.0, u0, u1, y0 - 0.06, y0, 0.1, trim)
	for x: float in [u0, u1]:
		_out(p, n, true, f, 1.0, x - 0.17, x + 0.17, 0.22, y0 - 0.26, 0.1, pil)
		_out(p, n, true, f, 1.0, x - 0.2, x + 0.2, y0 - 0.26, y0 - 0.06, 0.13, trim)
		_out(p, n, true, f, 1.0, x - 0.2, x + 0.2, 0.0, 0.22, 0.13, trim.darkened(0.15))
	for wnd: Array in windows:
		var a: float = wnd[0]
		var e: float = wnd[1]
		var sill: float = wnd[2]
		_out(p, n, true, f, 1.0, a - FRAME, e + FRAME, 0.0, sill - FRAME - 0.06, 0.05, riser)
		_out(p, n, true, f, 1.0, a - FRAME - 0.03, e + FRAME + 0.03, sill - FRAME - 0.06, sill - FRAME, 0.12, trim)


## A pent roof of clay barrel tiles on a street front, as on a Spanish-revival
## front or over its door: on the face of the front wall at v, from u0 to u1, its
## back edge on the wall at height y, reaching `deep` out and falling `pitch`
## degrees; boards and rafter ends under it, and along its eave the round end of
## each run of tiles. Give it in_rooftile at 1.6 m a tile (`look`), and the round
## ends fall on the texture's crowns. Returns its group (tipped by `pitch`).
static func pent(p: Node3D, n: Node3D, v: float, u0: float, u1: float, y: float, deep := 0.6, pitch := 24.0, look: Variant = Color(0.74, 0.32, 0.2), wood := Color(0.34, 0.2, 0.13), eave := Color(0.6, 0.24, 0.14)) -> Node3D:
	var f := v + T * 0.5
	var w := u1 - u0
	var long := deep / cos(deg_to_rad(pitch))
	var g := Kit.group(n, p.pt((u0 + u1) * 0.5, f, y), Vector3(pitch, 0, 0))
	# Each piece overlaps the next a little: none shares a face with another.
	Kit.box(g, Vector3(w, 0.07, long), Vector3(0, -0.035, long * 0.5), look)                            # the tiles
	Kit.box(g, Vector3(w - 0.02, 0.04, long - 0.03), Vector3(0, -0.07, long * 0.5 - 0.015), wood)       # the boards under them
	var count := maxi(int(w / 0.45), 1)
	for i in count + 1:
		var x := -w * 0.5 + 0.05 + (w - 0.1) * float(i) / count
		Kit.box(g, Vector3(0.06, 0.08, long - 0.06), Vector3(x, -0.115, long * 0.5 - 0.03), wood.darkened(0.2))     # a rafter's end
	var gx: float = g.position.x
	var k := ceili((gx - w * 0.5 + 0.05 - 0.097) / 0.2)
	while k * 0.2 + 0.097 < gx + w * 0.5 - 0.05:
		Kit.cyl(g, 0.046, 0.08, Vector3(k * 0.2 + 0.097 - gx, -0.004, long - 0.01), eave, Vector3(90, 0, 0), 8)
		k += 1
	return g


## A wrought-iron balconette on a street front, in front of a window: a shallow
## floor on two brackets, a rail of bars with returns to the wall and a pair of
## scrolls in the middle. On the face of the front wall at v; (u, y) is the
## middle of the top of its floor, w long, `deep` out from the wall.
static func balconette(p: Node3D, n: Node3D, u: float, v: float, y: float, w := 1.4, deep := 0.32, look := Color(0.12, 0.12, 0.14)) -> Node3D:
	var g := Kit.group(n, p.pt(u, v + T * 0.5, y))
	var front := deep - 0.02
	Kit.box(g, Vector3(w, 0.05, deep), Vector3(0, -0.025, deep * 0.5), look)                  # the floor
	for s: float in [-1.0, 1.0]:
		var x := s * (w * 0.5 - 0.08)
		Kit.tube(g, Vector3(x, -0.36, 0.015), Vector3(x, -0.045, deep - 0.05), 0.016, look, 4)       # a bracket
		Kit.box(g, Vector3(0.03, 0.74, 0.03), Vector3(s * (w * 0.5 - 0.015), 0.37, front), look)      # a corner post
		Kit.box(g, Vector3(0.026, 0.026, front - 0.015), Vector3(s * (w * 0.5 - 0.015), 0.7, (front - 0.015) * 0.5), look)   # the return
	Kit.box(g, Vector3(w + 0.02, 0.045, 0.045), Vector3(0, 0.74, front), look)                # the top rail
	Kit.box(g, Vector3(w, 0.03, 0.03), Vector3(0, 0.1, front), look)                          # the bottom rail
	var bars := maxi(int(w / 0.12), 2)
	for i in range(1, bars):
		var x := -w * 0.5 + w * float(i) / bars
		if absf(x) < 0.2:
			continue
		Kit.box(g, Vector3(0.016, 0.6, 0.016), Vector3(x, 0.41, front), look)
	for s: float in [-1.0, 1.0]:          # the scrolls
		Kit.ring(g, 0.1, 0.018, Vector3(s * 0.1, 0.42, front), look)
		Kit.ring(g, 0.045, 0.014, Vector3(s * 0.1, 0.42, front), look)
	return g


## A lantern hung on a chain (under a canopy, a porch roof): a pyramid cap,
## four glowing panes between dark corner posts, a base and a drop finial.
## `top` is where its chain hangs from in `parent`; its base is `drop` under it.
static func lantern(parent: Node3D, top: Vector3, drop := 0.4, look := Color(0.12, 0.12, 0.14), glow := WARM) -> Node3D:
	var g := Kit.group(parent, top)
	var h := 0.26
	var base := -drop
	var chain := drop - h - 0.07
	if chain > 0.01:
		Kit.cyl(g, 0.008, chain, Vector3(0, -chain * 0.5, 0), look, Vector3.ZERO, 4)
	Kit.cyl(g, 0.125, 0.08, Vector3(0, base + h + 0.035, 0), look, Vector3(0, 45, 0), 4, 0.02)     # the cap
	Kit.box(g, Vector3(0.15, h - 0.04, 0.15), Vector3(0, base + h * 0.5 + 0.01, 0), Kit.flat(glow, 1.6))
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		Kit.box(g, Vector3(0.025, h, 0.025), Vector3(s.x * 0.08, base + h * 0.5, s.y * 0.08), look)
	Kit.box(g, Vector3(0.2, 0.03, 0.2), Vector3(0, base + 0.015, 0), look)
	Kit.cyl(g, 0.025, 0.07, Vector3(0, base - 0.035, 0), look, Vector3.ZERO, 6, 0.0)
	return g


# ------------------------------------------------------------ on ward walls

## A bed-head unit on a ward's wall over the head of a bed: a long cased panel
## `w` wide, its middle at height y, a light along its top edge; on its face the
## oxygen outlet with its flowmeter, the suction outlet with its jar, two
## sockets, and the nurse-call handset hanging on its cord off the end.
static func bedhead(p: Node3D, b: Variant, u: float, v: float, yaw := 0.0, w := 1.4, y := 1.6, look := Color(0.93, 0.9, 0.82)) -> Node3D:
	var g := Kit.group(_node(p, b), p.pt(u, v), Vector3(0, yaw, 0))
	Kit.bevel(g, Vector3(w, 0.26, 0.08), Vector3(0, y, 0.04), look, 0.02)
	Kit.box(g, Vector3(w - 0.08, 0.035, 0.03), Vector3(0, y + 0.118, 0.085), Kit.flat(TUBE, 1.4))     # the light, a lip along the top
	Kit.box(g, Vector3(w - 0.05, 0.018, 0.004), Vector3(0, y + 0.07, 0.081), look.darkened(0.2))        # the seam under it
	var green := Color(0.16, 0.56, 0.3)
	var amber := Color(0.95, 0.76, 0.12)
	var clear := Color(0.86, 0.95, 1.0, 0.6)
	var x0 := -w * 0.5 + 0.16
	Kit.disc(g, 0.038, Vector3(x0, y - 0.02, 0.084), green, 0.01, 12)               # oxygen, and its flowmeter
	Kit.cyl(g, 0.024, 0.15, Vector3(x0, y - 0.14, 0.1), clear, Vector3.ZERO, 8)
	Kit.ball(g, 0.013, Vector3(x0, y - 0.11, 0.1), Kit.flat(Color(0.98, 0.98, 0.95), 0.4), 6)
	Kit.cyl(g, 0.028, 0.03, Vector3(x0, y - 0.23, 0.1), green, Vector3.ZERO, 8)
	var x1 := x0 + 0.17
	Kit.disc(g, 0.038, Vector3(x1, y - 0.02, 0.084), amber, 0.01, 12)               # suction, and its jar
	Kit.cyl(g, 0.055, 0.03, Vector3(x1, y - 0.12, 0.11), amber, Vector3.ZERO, 10)
	Kit.cyl(g, 0.05, 0.16, Vector3(x1, y - 0.215, 0.11), clear, Vector3.ZERO, 10)
	for k in 2:                                                                     # two sockets
		var sx := w * 0.5 - 0.42 + k * 0.13
		Kit.bevel(g, Vector3(0.1, 0.1, 0.02), Vector3(sx, y - 0.03, 0.088), Color(0.98, 0.97, 0.94), 0.008)
		for s: float in [-1.0, 1.0]:
			Kit.box(g, Vector3(0.008, 0.026, 0.004), Vector3(sx + s * 0.018, y - 0.03, 0.099), Props.DARK)
	var hx := w * 0.5 - 0.12                                                        # the call handset
	Kit.tube(g, Vector3(hx, y - 0.11, 0.07), Vector3(hx + 0.02, y - 0.5, 0.1), 0.006, Props.DARK, 4)
	Kit.bevel(g, Vector3(0.06, 0.15, 0.04), Vector3(hx + 0.02, y - 0.58, 0.1), Color(0.92, 0.9, 0.84), 0.015)
	Kit.cyl(g, 0.016, 0.012, Vector3(hx + 0.02, y - 0.55, 0.124), Kit.flat(Color(0.95, 0.15, 0.12), 0.8), Vector3(90, 0, 0), 8)
	return g


## A rack of glove boxes on a wall: a wire frame holding three boxes side by
## side, blue, violet and green, a glove puffing out of each one's slot. Its
## middle at height y.
static func gloves(p: Node3D, b: Variant, u: float, v: float, yaw := 0.0, y := 1.5) -> Node3D:
	var g := Kit.group(_node(p, b), p.pt(u, v), Vector3(0, yaw, 0))
	var cols := [Color(0.2, 0.42, 0.85), Color(0.55, 0.32, 0.78), Color(0.25, 0.65, 0.42)]
	for k in 3:
		var x := (k - 1) * 0.145
		var c: Color = cols[k]
		Kit.bevel(g, Vector3(0.13, 0.24, 0.085), Vector3(x, y, 0.05), c, 0.012)
		Kit.bevel(g, Vector3(0.09, 0.03, 0.012), Vector3(x, y + 0.06, 0.093), Color(0.97, 0.97, 0.95), 0.008)     # the slot
		Kit.ball(g, 0.032, Vector3(x, y + 0.066, 0.1), c.lightened(0.45), 6)                                  # a glove
		Kit.box(g, Vector3(0.1, 0.05, 0.004), Vector3(x, y - 0.06, 0.0945), Color(0.97, 0.97, 0.95))        # the label
	for s: float in [-1.0, 1.0]:                                                                           # the wire rack
		Kit.box(g, Vector3(0.012, 0.28, 0.1), Vector3(s * 0.225, y, 0.05), Props.STEEL)
	Kit.box(g, Vector3(0.438, 0.012, 0.1), Vector3(0, y - 0.126, 0.05), Props.STEEL)
	Kit.box(g, Vector3(0.438, 0.012, 0.012), Vector3(0, y + 0.03, 0.098), Props.STEEL)
	return g


## A sharps bin on a wall bracket: a yellow box under a red lid with the slot
## in it, a label on its front. Its middle at height y.
static func sharps(p: Node3D, b: Variant, u: float, v: float, yaw := 0.0, y := 1.4) -> Node3D:
	var g := Kit.group(_node(p, b), p.pt(u, v), Vector3(0, yaw, 0))
	Kit.box(g, Vector3(0.16, 0.3, 0.02), Vector3(0, y - 0.02, 0.01), Props.STEEL)                    # the bracket
	Kit.bevel(g, Vector3(0.22, 0.26, 0.15), Vector3(0, y - 0.02, 0.095), Color(0.98, 0.82, 0.12), 0.02)
	Kit.bevel(g, Vector3(0.24, 0.06, 0.17), Vector3(0, y + 0.13, 0.095), Color(0.86, 0.14, 0.12), 0.02)
	Kit.box(g, Vector3(0.12, 0.012, 0.05), Vector3(0, y + 0.162, 0.12), Props.DARK)                  # the slot
	Kit.box(g, Vector3(0.14, 0.08, 0.004), Vector3(0, y - 0.03, 0.172), Color(0.98, 0.97, 0.94))     # its label
	return g


## A hand-gel dispenser on a wall: a white case, a window showing the blue gel,
## a grey push plate, a drip tray under it. Its middle at height y.
static func gel(p: Node3D, b: Variant, u: float, v: float, yaw := 0.0, y := 1.3) -> Node3D:
	var g := Kit.group(_node(p, b), p.pt(u, v), Vector3(0, yaw, 0))
	Kit.bevel(g, Vector3(0.13, 0.24, 0.1), Vector3(0, y, 0.05), Color(0.97, 0.97, 0.95), 0.025)
	Kit.box(g, Vector3(0.05, 0.09, 0.006), Vector3(0, y + 0.04, 0.101), Kit.flat(Color(0.3, 0.6, 0.95), 0.3))
	Kit.bevel(g, Vector3(0.1, 0.07, 0.03), Vector3(0, y - 0.07, 0.105), Color(0.6, 0.62, 0.66), 0.01)
	Kit.box(g, Vector3(0.1, 0.012, 0.08), Vector3(0, y - 0.2, 0.06), Props.STEEL)
	return g


## The diagnostic set on an examining room's wall: a cream panel with its two
## instruments standing in their holders, their coiled cords hanging under it,
## and beside it the blood-pressure gauge, its cuff rolled up in a basket under
## the dial. Its middle at height y; about 0.62 wide.
static func diagnostic(p: Node3D, b: Variant, u: float, v: float, yaw := 0.0, y := 1.5) -> Node3D:
	var g := Kit.group(_node(p, b), p.pt(u, v), Vector3(0, yaw, 0))
	Kit.bevel(g, Vector3(0.4, 0.2, 0.06), Vector3(-0.12, y, 0.03), Color(0.94, 0.91, 0.82), 0.02)
	for k in 2:
		var x := -0.22 + k * 0.2
		Kit.cyl(g, 0.03, 0.05, Vector3(x, y + 0.08, 0.075), Props.STEEL, Vector3.ZERO, 8)           # the holder
		Kit.cyl(g, 0.02, 0.16, Vector3(x, y + 0.17, 0.075), Props.DARK, Vector3.ZERO, 8)            # the handle
		if k == 0:      # the otoscope's cone
			Kit.cyl(g, 0.012, 0.09, Vector3(x + 0.03, y + 0.27, 0.075), Props.DARK, Vector3(0, 0, -70), 8, 0.03)
		else:           # the ophthalmoscope's head
			Kit.bevel(g, Vector3(0.05, 0.07, 0.03), Vector3(x, y + 0.28, 0.075), Props.DARK, 0.012)
		for c in 5:     # the coiled cord
			Kit.ring(g, 0.016, 0.006, Vector3(x, y - 0.12 - c * 0.025, 0.07), Props.DARK, Vector3(-90, 0, 0))
	Kit.bevel(g, Vector3(0.2, 0.24, 0.07), Vector3(0.2, y + 0.04, 0.035), Props.DARK, 0.02)        # the gauge
	Kit.disc(g, 0.085, Vector3(0.2, y + 0.05, 0.075), Color(0.98, 0.97, 0.94), 0.008, 16)
	for k in 9:
		var a := deg_to_rad(-120.0 + k * 30.0)
		Kit.box(g, Vector3(0.006, 0.016, 0.003), Vector3(0.2 + sin(a) * 0.066, y + 0.05 + cos(a) * 0.066, 0.0805), Props.DARK, Vector3(0, 0, -rad_to_deg(a)))
	Kit.box(g, Vector3(0.006, 0.07, 0.003), Vector3(0.214, y + 0.078, 0.082), Color(0.85, 0.12, 0.1), Vector3(0, 0, -25))
	Kit.bevel(g, Vector3(0.2, 0.1, 0.1), Vector3(0.2, y - 0.17, 0.06), Props.DARK, 0.015)          # the basket, the cuff in it
	Kit.bevel(g, Vector3(0.17, 0.08, 0.07), Vector3(0.2, y - 0.13, 0.065), Color(0.16, 0.24, 0.46), 0.025)
	return g
