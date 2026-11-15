extends RefCounted
## Props for the service alley behind the strip (plans/service.gd; the strip
## worker's): a panel van with its back doors open, wheelie bins, a stack of
## pallets, roll cages of stock, a bale of cardboard, a hand truck, an air
## conditioner on its bracket, a chain-link gate, and the steel back door drawn
## on a wall from inside (the corner store's and the clothing store's stock
## rooms, the studio's booth); the studio's back stair, and on its roof the back
## of its sign, a condenser and a skylight. Names and words on them are
## placeholders.

const Props := preload("res://scripts/props.gd")
const Outdoor := preload("res://scripts/outdoor.gd")
const Park := preload("res://scripts/props_park.gd")

const DARK := Color(0.1, 0.1, 0.11)
const RUBBER := Color(0.07, 0.07, 0.08)
const GALV := Color(0.6, 0.62, 0.64)
const CARD := Color(0.66, 0.5, 0.32)


## A box on the plan: u0..u1, v0..v1, y0..y1.
static func gb(p: Node3D, n: Node3D, u0: float, u1: float, v0: float, v1: float, y0: float, y1: float, look: Variant) -> MeshInstance3D:
	return Kit.box(n, Vector3(u1 - u0, y1 - y0, v1 - v0), p.pt((u0 + u1) * 0.5, (v0 + v1) * 0.5, (y0 + y1) * 0.5), look)


## A steel back door drawn on a wall from inside (a picture of one: E at the
## use point in front goes through): its frame, the leaf, a kick plate, the
## push bar on its brackets. Into `g`, a group on the wall's face (a dressed
## wall's skin) turned to face out of the wall.
static func steel_door(g: Node3D, look := Color(0.36, 0.4, 0.43)) -> Node3D:
	var frame := Color(0.2, 0.21, 0.23)
	Kit.box(g, Vector3(1.1, 2.18, 0.03), Vector3(0, 1.09, 0.015), frame)
	Kit.box(g, Vector3(0.96, 2.08, 0.03), Vector3(0, 1.04, 0.04), look)
	Kit.box(g, Vector3(0.96, 0.26, 0.004), Vector3(0, 0.15, 0.057), look.lightened(0.15))
	Kit.box(g, Vector3(0.8, 0.07, 0.05), Vector3(0, 1.0, 0.08), Props.STEEL)
	for x: float in [-0.4, 0.4]:
		Kit.box(g, Vector3(0.06, 0.12, 0.08), Vector3(x, 1.0, 0.07), frame)      # 5 mm proud of the bar
	return g


## A panel van parked with its front facing `yaw` (it takes its floor), 5.2 long
## and 2.0 wide: a high box, the cab and its bonnet, the back doors swung open on
## the dark of the load space with boxes in it, `words` along its left side
## only (the side that is seen: a word stays solid while CarFade ghosts the van,
## so one on the far side would show through it backwards).
static func van(p: Node3D, b: int, u: float, v: float, yaw: float, paint: Color, words := "") -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 2.0, 5.2)
	var glass := Color(0.16, 0.21, 0.28)
	var seam := paint.darkened(0.45)
	Kit.bevel_block(g, Vector3(2.0, 1.88, 3.54), Vector3(0, 0.38, -0.81), paint, 0.08)        # the box, z -2.58 .. 0.96
	Kit.bevel_block(g, Vector3(1.98, 1.55, 0.95), Vector3(0, 0.38, 1.4), paint, 0.1)          # the cab
	Kit.bevel_block(g, Vector3(1.94, 0.72, 0.76), Vector3(0, 0.38, 2.2), paint, 0.1)          # the bonnet, to 2.58
	Kit.pane(Kit.box(g, Vector3(1.76, 0.66, 0.03), Vector3(0, 1.55, 1.86), glass, Vector3(-12, 0, 0)))
	Kit.box(g, Vector3(1.06, 0.28, 0.02), Vector3(0, 0.82, 2.585), DARK)                      # the grille (clear of the lamps)
	for s: float in [-1.0, 1.0]:
		Kit.pane(Kit.box(g, Vector3(0.02, 0.48, 0.6), Vector3(s * 0.995, 1.58, 1.42), glass))
		Kit.box(g, Vector3(0.08, 0.22, 0.12), Vector3(s * 1.08, 1.5, 1.8), DARK)              # a mirror
		Kit.box(g, Vector3(0.28, 0.15, 0.02), Vector3(s * 0.7, 0.86, 2.585), Kit.flat(Color(0.98, 0.95, 0.8), 0.35))
		Kit.box(g, Vector3(0.12, 0.42, 0.02), Vector3(s * 0.93, 1.05, -2.6), Kit.flat(Color(0.85, 0.12, 0.1), 0.45))
		Kit.box(g, Vector3(0.012, 1.5, 0.02), Vector3(s * 1.006, 1.2, 0.5), seam)              # the sliding door's seam, over...
		Kit.box(g, Vector3(0.01, 0.14, 3.4), Vector3(s * 1.003, 0.98, -0.85), paint.darkened(0.3))    # ...a stripe
		if words != "" and s < 0.0:
			Props.words(g, words, Vector3(s * 1.012, 1.62, -0.85), 0.22, Color(0.18, 0.3, 0.55), 90.0 * s)
	for z: float in [2.62, -2.63]:
		Kit.bevel(g, Vector3(2.04, 0.18, 0.12), Vector3(0, 0.46, z), DARK, 0.04)
	# The wheels: a dark well behind each, the tyre, the hub.
	for x: float in [-0.92, 0.92]:
		for z: float in [-1.7, 1.75]:
			Kit.cyl(g, 0.46, 0.03, Vector3(signf(x) * 1.004, 0.42, z), RUBBER, Vector3(0, 0, 90), 20)
			Kit.cyl(g, 0.37, 0.26, Vector3(x, 0.37, z), RUBBER, Vector3(0, 0, 90), 20)
			Kit.cyl(g, 0.16, 0.27, Vector3(x, 0.37, z), Props.STEEL, Vector3(0, 0, 90), 12)
	# The back: the right-hand door shut, the left-hand one swung out from its
	# corner (the floor it stands on is the plan's to keep), the load space seen
	# through the half it opened, boxes in it.
	Kit.box(g, Vector3(0.84, 1.78, 0.03), Vector3(0.43, 1.33, -2.61), paint)          # between the tail lamps
	Kit.box(g, Vector3(0.56, 0.42, 0.012), Vector3(0.43, 1.83, -2.632), glass)
	Kit.box(g, Vector3(0.8, 1.7, 0.01), Vector3(-0.45, 1.3, -2.59), Color(0.06, 0.06, 0.07))
	for box: Array in [[-0.62, 0.64, 0.4, 0.46], [-0.3, 0.62, 0.3, 0.42], [-0.5, 1.08, 0.5, 0.4]]:
		Kit.box(g, Vector3(box[2], box[3], 0.03), Vector3(box[0], box[1], -2.62), CARD.darkened(0.25))
	for y: float in [0.79, 1.89]:                  # its hinges, at the corner it swung from
		Kit.box(g, Vector3(0.05, 0.13, 0.07), Vector3(-0.875, y, -2.613), DARK)
	var leaf := Kit.group(g, Vector3(-0.86, 0.44, -2.6), Vector3(0, 100.0, 0))
	Kit.box(leaf, Vector3(0.84, 1.78, 0.04), Vector3(0.42, 0.9, -0.02), paint)
	Kit.box(leaf, Vector3(0.56, 0.42, 0.012), Vector3(0.42, 1.4, -0.045), glass)
	return g


## A wheelie bin with its back (the handle, the wheels) to the wall, 0.6 wide.
static func wheelie_bin(p: Node3D, b: int, u: float, v: float, yaw: float, look: Color) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.62, 0.74)
	Kit.bevel_block(g, Vector3(0.56, 0.9, 0.66), Vector3(0, 0.06, 0.02), look, 0.04)
	Kit.bevel(g, Vector3(0.62, 0.06, 0.74), Vector3(0, 0.99, 0.0), look.darkened(0.25), 0.02)
	Kit.box(g, Vector3(0.48, 0.05, 0.05), Vector3(0, 0.96, -0.36), DARK)
	for x: float in [-0.22, 0.22]:
		Kit.cyl(g, 0.1, 0.06, Vector3(x, 0.1, -0.28), RUBBER, Vector3(0, 0, 90), 10)
	return g


## A stack of `n` wooden pallets, 1.2 wide by 1.0, each a little askew: the deck
## boards, three runners from front to back with the dark of the fork holes
## between them, the boards under them.
static func pallets(p: Node3D, b: int, u: float, v: float, yaw: float, n := 4) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.24, 1.04)
	var wood := Kit.tex("in_planks", 0.5, Color(0.6, 0.48, 0.32), true, Color(0.86, 0.74, 0.56))
	var hole := Color(0.09, 0.08, 0.07)
	for k in n:
		var r := Props.rnd(u * 1.7 + k * 2.3)
		var one := Kit.group(g, Vector3((r - 0.5) * 0.05, k * 0.144, 0), Vector3(0, (r - 0.5) * 6.0, 0))
		Kit.box(one, Vector3(1.2, 0.022, 1.0), Vector3(0, 0.011, 0), wood)
		Kit.box(one, Vector3(0.98, 0.09, 0.96), Vector3(0, 0.067, 0), hole)      # (its faces off the runners')
		for x: float in [-0.55, 0.0, 0.55]:
			Kit.box(one, Vector3(0.1, 0.1, 1.0), Vector3(x, 0.072, 0), wood)
		Kit.box(one, Vector3(1.2, 0.022, 1.0), Vector3(0, 0.133, 0), wood)
	return g


## A roll cage of stock on its castors, 0.8 wide: a galvanised frame, mesh on
## its back and ends, red straps across its open front, boxes inside.
static func cage(p: Node3D, b: int, u: float, v: float, yaw: float, look := CARD) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.84, 0.74)
	var mesh := Outdoor.chain_link(0.3)
	Kit.box(g, Vector3(0.8, 0.05, 0.7), Vector3(0, 0.17, 0), GALV)
	for x: float in [-0.36, 0.36]:
		for z: float in [-0.3, 0.3]:
			Kit.cyl(g, 0.06, 0.04, Vector3(x, 0.07, z), RUBBER, Vector3(0, 0, 90), 8)
	for x: float in [-0.39, 0.39]:
		Kit.box(g, Vector3(0.01, 1.55, 0.68), Vector3(x, 0.97, 0), mesh)
		for z: float in [-0.34, 0.34]:
			Kit.box(g, Vector3(0.03, 1.62, 0.03), Vector3(x, 0.98, z), GALV)
	Kit.box(g, Vector3(0.78, 1.55, 0.01), Vector3(0, 0.97, -0.34), mesh)
	for z: float in [-0.34, 0.34]:
		Kit.box(g, Vector3(0.81, 0.03, 0.03), Vector3(0, 1.78, z), GALV)
	for y: float in [0.85, 1.4]:
		Kit.box(g, Vector3(0.8, 0.04, 0.01), Vector3(0, y, 0.362), Color(0.8, 0.2, 0.16))      # in front of the posts
	Kit.box(g, Vector3(0.7, 0.44, 0.6), Vector3(0, 0.42, 0), look)
	Kit.box(g, Vector3(0.62, 0.4, 0.56), Vector3(0.03, 0.84, -0.01), look.lightened(0.12))
	Kit.box(g, Vector3(0.5, 0.34, 0.5), Vector3(-0.06, 1.21, 0.02), look.darkened(0.1))
	return g


## A bale of flattened cardboard, strapped, 1.1 wide.
static func bale(p: Node3D, b: int, u: float, v: float, yaw: float) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.1, 0.8)
	Kit.box(g, Vector3(1.1, 0.78, 0.8), Vector3(0, 0.39, 0), Kit.tex("in_ribbed", 0.3, CARD, false, Color(0.9, 0.78, 0.62)))
	for x: float in [-0.32, 0.32]:
		Kit.box(g, Vector3(0.03, 0.8, 0.82), Vector3(x, 0.39, 0), Color(0.18, 0.2, 0.24))
	return g


## A hand truck stood up with three cases on its foot.
static func hand_truck(p: Node3D, b: int, u: float, v: float, yaw: float, look := Color(0.2, 0.3, 0.55)) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 0.56, 0.5)
	for x: float in [-0.2, 0.2]:
		Kit.box(g, Vector3(0.035, 1.3, 0.035), Vector3(x, 0.7, -0.16), Color(0.75, 0.15, 0.12))
		Kit.cyl(g, 0.12, 0.06, Vector3(x * 1.25, 0.12, -0.12), RUBBER, Vector3(0, 0, 90), 10)
	Kit.box(g, Vector3(0.44, 0.035, 0.035), Vector3(0, 1.33, -0.16), Color(0.75, 0.15, 0.12))
	Kit.box(g, Vector3(0.44, 0.02, 0.26), Vector3(0, 0.04, 0.0), Props.STEEL)
	for k in 3:
		Kit.box(g, Vector3(0.4, 0.26, 0.3), Vector3(0, 0.18 + k * 0.27, 0.0), look if k != 1 else look.lightened(0.2))
	return g


## An air conditioner on its bracket high on a wall facing +v, at (u, wall) and y.
static func ac_unit(p: Node3D, n: Node3D, u: float, v: float, y: float) -> Node3D:
	var g := Kit.group(n, p.pt(u, v))
	Kit.bevel(g, Vector3(0.9, 0.62, 0.38), Vector3(0, y, 0.24), Color(0.78, 0.78, 0.74), 0.03)
	Kit.disc(g, 0.21, Vector3(0.14, y, 0.432), DARK, 0.01, 16)
	Kit.ring(g, 0.21, 0.025, Vector3(0.14, y, 0.44), Props.STEEL)
	for x: float in [-0.34, 0.34]:
		Kit.box(g, Vector3(0.06, 0.06, 0.44), Vector3(x, y - 0.34, 0.22), GALV)      # its brackets (grey: thin and black they read as cables)
	return g


## A galvanised steel stair up a back wall to its roof (the wall on v = 0 of the
## plan; the stair stands v0 off it), rising toward -u from the ground at y0:
## the bottom step's nose at u_foot, the flight up to a landing (u_top - 1.0 ..
## u_top) `rise` up, level with the roof behind the gap left in its parapet.
## Treads between two stringers, a guard rail along the open side and round the
## landing's end, a handrail on the wall, a post under the flight, brackets
## under the landing. Drawn into `n`, taking no floor: the plan keeps the floor
## under its low end clear (the post stands in that).
static func back_stair(p: Node3D, n: Node3D, u_foot: float, u_top: float, v0: float, y0: float, rise: float) -> void:
	var w := 0.85                                  # between the stringers
	var steps := maxi(roundi(rise / 0.19), 2)
	var r := rise / float(steps)
	var g := (u_foot - u_top) / float(steps - 1)
	var foot := Vector2(u_foot + g, y0)            # the line of the noses (u, y), from the ground...
	var head := Vector2(u_top, y0 + rise)          # ...to the landing's edge
	var line := head - foot
	var ang := rad_to_deg(atan2(line.y, -line.x))
	var vo := v0 + 0.075 + w                       # the outer stringer's middle
	var top := y0 + rise
	var tread := GALV.darkened(0.2)
	for k in range(1, steps):
		var nose := u_foot - float(k - 1) * g
		gb(p, n, nose - g - 0.015, nose, v0 + 0.05, v0 + 0.05 + w, y0 + k * r - 0.035, y0 + k * r, tread)
	# The stringers, their tops 8 cm over the line of the noses.
	var mid := foot.lerp(head, 0.5) + Vector2(-line.y, line.x).normalized() * 0.05
	for v: float in [v0 + 0.025, vo]:
		Kit.box(n, Vector3(line.length(), 0.26, 0.05), p.pt(mid.x, v, mid.y), GALV, Vector3(0, 0, -ang))
	# The guard along the open side: posts, a rail 0.95 over the noses and one between.
	for f: float in [0.06, 0.37, 0.68, 1.0]:
		var at := foot.lerp(head, f)
		Kit.box(n, Vector3(0.045, 0.95, 0.045), p.pt(at.x, vo, at.y + 0.475), GALV)
	var low := foot.lerp(head, 0.06)
	for hy: float in [0.95, 0.5]:
		Kit.tube(n, p.pt(low.x, vo, low.y + hy), p.pt(head.x, vo, head.y + hy), 0.024, GALV)
	# The handrail on the wall, on its brackets.
	low = foot.lerp(head, 0.04)
	Kit.tube(n, p.pt(low.x, v0 - 0.05, low.y + 0.9), p.pt(head.x, v0 - 0.05, head.y + 0.9), 0.022, GALV)
	for f: float in [0.15, 0.55, 0.92]:
		var at := foot.lerp(head, f)
		Kit.box(n, Vector3(0.04, 0.04, v0 - 0.03), p.pt(at.x, (v0 - 0.03) * 0.5, at.y + 0.9), GALV)
	# A post under the flight, on its plate.
	var under := foot.lerp(head, 0.45)
	gb(p, n, under.x - 0.12, under.x + 0.12, vo - 0.12, vo + 0.12, y0, y0 + 0.02, GALV.darkened(0.25))
	gb(p, n, under.x - 0.045, under.x + 0.045, vo - 0.045, vo + 0.045, y0 + 0.02, under.y - 0.2, GALV)
	# The landing: its deck level with the roof, edged; posts and rails round its
	# open side and its end; brackets under it into the wall.
	var u0 := u_top - 1.0
	gb(p, n, u0, u_top, 0.0, vo - 0.03, top - 0.04, top, tread)
	gb(p, n, u0, u_top, vo - 0.03, vo + 0.03, top - 0.2, top + 0.03, GALV)
	gb(p, n, u0 - 0.06, u0, 0.0, vo + 0.03, top - 0.2, top + 0.03, GALV)
	for v: float in [vo, 0.06]:
		Kit.box(n, Vector3(0.045, 0.92, 0.045), p.pt(u0 - 0.03, v, top + 0.49), GALV)
	for hy: float in [0.95, 0.5]:
		Kit.tube(n, p.pt(u0 - 0.03, vo, top + hy), p.pt(u_top, vo, top + hy), 0.024, GALV)
		Kit.tube(n, p.pt(u0 - 0.03, vo, top + hy - 0.01), p.pt(u0 - 0.03, 0.06, top + hy - 0.01), 0.023, GALV)
	for u: float in [u0 + 0.12, u_top - 0.12]:
		Kit.tube(n, p.pt(u, vo - 0.05, top - 0.2), p.pt(u, -0.02, top - 1.0), 0.03, GALV)


## The back of a sign standing on a roof's front edge, its face to the street
## (-v), the board's back on v: from the roof, the board's plain sheet, the
## rails across it, its three posts braced back to the roof, and the lamps'
## arms reaching over its top to light the face, their glow round its edges.
## It takes the roof under it.
static func roof_sign(p: Node3D, b: int, u0: float, u1: float, v: float, look := Color(0.44, 0.46, 0.47)) -> void:
	var n: Node3D = p.node_of(b)
	var rust := Color(0.44, 0.26, 0.18)
	var mid := (u0 + u1) * 0.5
	p.block(u0 - 0.15, v - 0.2, u1 + 0.15, v + 1.4)
	gb(p, n, u0, u1, v - 0.06, v, 1.1, 2.6, look)
	gb(p, n, u0 + 0.04, u1 - 0.04, v - 0.07, v - 0.06, 1.14, 2.56, Color(0.16, 0.2, 0.34))      # its face, the street's side
	for y: float in [1.4, 2.25]:
		gb(p, n, u0 + 0.05, u1 - 0.05, v, v + 0.05, y - 0.03, y + 0.03, rust)
	var k := 1
	while u0 + k * 0.62 < u1 - 0.3:                 # the sheet's seams, and the box its lamps are wired from
		gb(p, n, u0 + k * 0.62 - 0.0125, u0 + k * 0.62 + 0.0125, v + 0.001, v + 0.013, 1.12, 2.58, look.darkened(0.25))
		k += 1
	gb(p, n, mid + 0.9, mid + 1.15, v + 0.001, v + 0.12, 1.55, 1.8, Color(0.34, 0.35, 0.36))
	Kit.tube(n, p.pt(mid + 1.02, v + 0.06, 1.55), p.pt(mid + 1.02, v + 0.06, 0.02), 0.018, GALV)
	for u: float in [u0 + 0.25, mid, u1 - 0.25]:
		gb(p, n, u - 0.04, u + 0.04, v + 0.05, v + 0.13, 0.02, 2.75, rust)
		gb(p, n, u - 0.13, u + 0.13, v - 0.04, v + 0.22, 0.0, 0.02, rust.darkened(0.2))
		Kit.tube(n, p.pt(u, v + 0.13, 2.1), p.pt(u, v + 1.25, 0.02), 0.035, rust)
		gb(p, n, u - 0.12, u + 0.12, v + 1.13, v + 1.37, 0.0, 0.02, rust.darkened(0.2))
	for u: float in [u0 + 0.6, mid, u1 - 0.6]:
		Kit.tube(n, p.pt(u, v + 0.09, 2.3), p.pt(u, v + 0.09, 2.95), 0.022, GALV)
		Kit.tube(n, p.pt(u, v + 0.09, 2.95), p.pt(u, v - 0.55, 2.95), 0.022, GALV)
		gb(p, n, u - 0.1, u + 0.1, v - 0.68, v - 0.5, 2.84, 2.96, Color(0.3, 0.31, 0.33))
	Kit.omni(n, p.pt(mid, v - 1.1, 1.9), Color(1.0, 0.86, 0.62), 1.4, 4.5)


## An air conditioner's condenser on a roof: a louvred cabinet on two rails,
## the fan's grille on top.
static func condenser(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 1.1, 0.9)
	var look := Color(0.8, 0.79, 0.74)
	for z: float in [-0.3, 0.3]:
		Kit.box(g, Vector3(1.04, 0.1, 0.1), Vector3(0, 0.05, z), Color(0.34, 0.35, 0.37))
	Kit.bevel(g, Vector3(1.0, 0.78, 0.8), Vector3(0, 0.49, 0), look, 0.03)
	for k in 6:
		Kit.box(g, Vector3(0.86, 0.022, 0.012), Vector3(0, 0.22 + k * 0.1, 0.405), look.darkened(0.25))
	Kit.cyl(g, 0.32, 0.012, Vector3(0, 0.886, 0), Color(0.24, 0.25, 0.27), Vector3.ZERO, 18)
	Kit.ring(g, 0.32, 0.03, Vector3(0, 0.894, 0), Props.STEEL, Vector3(-90, 0, 0))
	for a: float in [0.0, 60.0, 120.0]:
		Kit.box(g, Vector3(0.6, 0.012, 0.03), Vector3(0, 0.898, 0), GALV, Vector3(0, a, 0))
	return g


## A skylight on its curb, lit from the room under it.
static func skylight(p: Node3D, b: int, u: float, v: float, w := 1.0, d := 0.8) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, w + 0.2, d + 0.2)
	Kit.box(g, Vector3(w + 0.16, 0.3, d + 0.16), Vector3(0, 0.15, 0), GALV.darkened(0.3))
	Kit.box(g, Vector3(w, 0.03, d), Vector3(0, 0.315, 0), Kit.flat(Color(1.0, 0.85, 0.6), 0.75))
	for x: float in [-w * 0.25, w * 0.25]:
		Kit.box(g, Vector3(0.03, 0.02, d), Vector3(x, 0.34, 0), GALV)
	return g


## A chain-link gate shut across the alley at u, from v0 to v1 (two leaves in
## galvanised frames between their posts), chained and padlocked in the middle.
static func gate(p: Node3D, n: Node3D, u: float, v0: float, v1: float, h := 2.2) -> void:
	var mid := (v0 + v1) * 0.5
	for leaf: Array in [[v0, mid - 0.02], [mid + 0.02, v1]]:
		var a: float = leaf[0]
		var b: float = leaf[1]
		Kit.box(n, Vector3(0.01, h - 0.12, b - a - 0.08), p.pt(u, (a + b) * 0.5, h * 0.5), Outdoor.chain_link())
		for y: float in [0.06, h * 0.5, h - 0.06]:
			Park.rod(n, p.pt(u, a + 0.04, y), p.pt(u, b - 0.04, y), 0.02, GALV, 5)
		for e: float in [a + 0.04, b - 0.04]:
			Park.rod(n, p.pt(u, e, 0.04), p.pt(u, e, h - 0.04), 0.02, GALV, 5)
	for e: float in [v0, v1]:
		Kit.cyl(n, 0.05, h + 0.15, p.pt(u, e, (h + 0.15) * 0.5), GALV, Vector3.ZERO, 8)
	Kit.ring(n, 0.07, 0.016, p.pt(u, mid, 1.08), Props.IRON, Vector3(0, 90, 0))
	Kit.box(n, Vector3(0.04, 0.09, 0.07), p.pt(u + 0.03, mid, 0.97), Props.STEEL)
