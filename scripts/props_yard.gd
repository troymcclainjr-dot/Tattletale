extends RefCounted
## Props for the police yard behind the station (plans/yard.gd; the civic
## worker's): the station's back door seen from the yard, the fuel island with
## its pump under a canopy, the vehicle gate in a side fence, police barricades,
## jersey barriers, and a sign wired to chain link. Words on them are
## placeholders.

const Props := preload("res://scripts/props.gd")
const Outdoor := preload("res://scripts/outdoor.gd")
const Service := preload("res://scripts/props_service.gd")
const Prison := preload("res://scripts/props_prison.gd")

const SAFETY := Color(0.93, 0.74, 0.12)
const CONCRETE := Color(0.7, 0.69, 0.66)
const FRAME := Color(0.36, 0.38, 0.4)


## The station's steel back door from the yard (a picture of one on the wall:
## E at the use point in front goes in): the leaf in its frame, w wide, a wired
## window, the pull, its foot kicked dull. In n, at (u, v) on the wall's face,
## facing `yaw`.
static func back_door(p: Node3D, n: Node3D, u: float, v: float, yaw: float, w := 0.95) -> Node3D:
	var g := Kit.group(n, p.pt(u, v), Vector3(0, yaw, 0))
	var steel := Color(0.4, 0.44, 0.47)
	Kit.box(g, Vector3(w, 2.16, 0.04), Vector3(0, 1.08, 0.02), Color(0.17, 0.18, 0.19))
	Kit.box(g, Vector3(w - 0.13, 2.06, 0.03), Vector3(0, 1.03, 0.05), steel)
	Kit.box(g, Vector3(w - 0.13, 0.28, 0.004), Vector3(0, 0.16, 0.067), steel.darkened(0.3))
	Kit.box(g, Vector3(0.24, 0.42, 0.012), Vector3(0, 1.55, 0.071), Color(0.24, 0.28, 0.32))
	Kit.pane(Kit.box(g, Vector3(0.18, 0.36, 0.006), Vector3(0, 1.55, 0.08), Color(0.5, 0.6, 0.66)))
	for y: float in [1.43, 1.55, 1.67]:         # its wire, steel (black reads as a cable)
		Kit.box(g, Vector3(0.18, 0.008, 0.004), Vector3(0, y, 0.085), Props.STEEL)
	Kit.box(g, Vector3(0.04, 0.3, 0.03), Vector3(w * 0.5 - 0.17, 1.05, 0.08), Props.STEEL)
	return g


## The fuel island (yaw 0: along u): a concrete island `long` long, the pump in
## its middle (a white cabinet, a blue band, a lit display on each face, the
## hose hung on its side), a yellow post at each end, and a flat canopy over it
## on two posts, lit from under. It keeps its floor clear.
static func fuel_island(p: Node3D, b: int, u: float, v: float, yaw := 0.0, long := 3.4) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, long, 0.9)
	Kit.bevel_block(g, Vector3(long, 0.16, 0.9), Vector3.ZERO, CONCRETE, 0.03)
	Kit.box(g, Vector3(long - 0.12, 0.004, 0.78), Vector3(0, 0.162, 0), CONCRETE.darkened(0.12))
	var blue := Color(0.16, 0.28, 0.56)
	Kit.bevel_block(g, Vector3(0.62, 1.5, 0.42), Vector3(0, 0.16, 0), Color(0.9, 0.9, 0.86), 0.03)
	Kit.box(g, Vector3(0.64, 0.24, 0.44), Vector3(0, 1.5, 0), blue)
	Kit.box(g, Vector3(0.68, 0.06, 0.48), Vector3(0, 1.66, 0), blue.darkened(0.3))
	for s: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(0.36, 0.2, 0.012), Vector3(0, 1.14, s * 0.216), Color(0.1, 0.12, 0.12))
		Kit.box(g, Vector3(0.28, 0.06, 0.006), Vector3(0, 1.17, s * 0.225), Kit.flat(Color(0.5, 0.95, 0.6), 1.0))
		Kit.box(g, Vector3(0.12, 0.1, 0.01), Vector3(0, 0.86, s * 0.218), Color(0.2, 0.2, 0.22))
	# The hose, out of the cabinet's side, down in a loop and up to the nozzle in its holster.
	var hose := Color(0.16, 0.16, 0.17)
	Kit.box(g, Vector3(0.08, 0.16, 0.12), Vector3(0.35, 1.0, 0.06), Color(0.2, 0.2, 0.22))
	Kit.box(g, Vector3(0.06, 0.22, 0.05), Vector3(0.36, 1.06, 0.06), Color(0.85, 0.2, 0.15), Vector3(0, 0, -14))
	var pts := [Vector3(0.32, 1.32, -0.08), Vector3(0.42, 0.9, -0.1), Vector3(0.47, 0.42, -0.04), Vector3(0.44, 0.32, 0.06), Vector3(0.4, 0.62, 0.1), Vector3(0.37, 0.96, 0.07)]
	for i in pts.size() - 1:
		Kit.tube(g, pts[i], pts[i + 1], 0.022, hose, 6)
	for s: float in [-1.0, 1.0]:                 # the posts at its ends
		var x := s * (long * 0.5 - 0.22)
		Kit.cyl(g, 0.1, 0.9, Vector3(x, 0.61, 0), SAFETY, Vector3.ZERO, 10)
		Kit.cyl(g, 0.104, 0.07, Vector3(x, 0.86, 0), Color(0.12, 0.12, 0.13), Vector3.ZERO, 10)
		Kit.ball(g, 0.1, Vector3(x, 1.06, 0), SAFETY, 8)
	# The canopy, on two square posts at the island's ends, its edge painted.
	for s: float in [-1.0, 1.0]:
		Kit.box(g, Vector3(0.2, 4.1, 0.2), Vector3(s * (long * 0.5 - 0.55), 2.21, 0), Color(0.86, 0.86, 0.84))      # (up into the canopy)
	Kit.box(g, Vector3(long + 1.8, 0.36, 4.2), Vector3(0, 4.34, 0), Color(0.88, 0.88, 0.86))
	Kit.box(g, Vector3(long + 1.84, 0.14, 4.24), Vector3(0, 4.3, 0), blue)
	Kit.box(g, Vector3(long + 1.4, 0.01, 3.8), Vector3(0, 4.15, 0), Kit.flat(Color(0.95, 0.96, 1.0), 0.5))       # (5 mm under it)
	return g


## The vehicle gate in a fence along v at u, shut and chained: chain link in a
## heavy frame with a brace in each half, on its track, from v0 to v1, h high,
## razor wire along its top and the sign on its yard side (+u). (props_prison.gd's
## vehicle_gate, turned to stand along v.)
static func side_gate(p: Node3D, n: Node3D, u: float, v0: float, v1: float, h: float) -> void:
	var mid := (v0 + v1) * 0.5
	var w := v1 - v0
	Kit.box(n, Vector3(0.012, h - 0.2, w - 0.2), p.pt(u, mid, h * 0.5 + 0.06), Outdoor.chain_link())
	for y: float in [0.12, h * 0.52, h - 0.02]:
		Kit.box(n, Vector3(0.08, 0.08, w - 0.1), p.pt(u, mid, y), FRAME)
	for k in 5:
		var z := v0 + 0.08 + (w - 0.16) * float(k) / 4.0
		Kit.box(n, Vector3(0.08, h - 0.04, 0.08), p.pt(u, z, h * 0.5 + 0.02), FRAME)
	for half: Array in [[v0 + 0.1, mid], [mid, v1 - 0.1]]:
		Kit.tube(n, p.pt(u - 0.05, half[0], 0.16), p.pt(u - 0.05, half[1], h - 0.06), 0.03, FRAME, 5)
	for v: float in [v0, v1]:                    # the posts it runs between, outside it
		Kit.cyl(n, 0.09, h + 0.3, p.pt(u - 0.14, v, (h + 0.3) * 0.5), FRAME.darkened(0.2), Vector3.ZERO, 10)
	Kit.box(n, Vector3(0.22, 0.05, w + 0.6), p.pt(u, mid, 0.025), Service.DARK)      # the track
	# Chained to the post it shuts on: a few links round the frame and the post, a padlock.
	for k in 4:
		Kit.box(n, Vector3(0.12, 0.035, 0.035), p.pt(u + 0.02, v1 - 0.06, 1.18 + k * 0.05), Props.STEEL, Vector3(0, 30.0 * (k % 2), 0))
	Kit.box(n, Vector3(0.03, 0.09, 0.07), p.pt(u + 0.07, v1 - 0.12, 1.08), Color(0.62, 0.5, 0.2))
	Kit.box(n, Vector3(0.03, 0.6, 1.6), p.pt(u + 0.06, mid, 1.55), Color(0.92, 0.9, 0.84))
	Props.words(n, "AUTHORIZED\nVEHICLES ONLY", p.pt(u + 0.08, mid, 1.55), 0.13, Color(0.7, 0.12, 0.1), 90.0)
	Prison.razor(n, p.pt(u, v0 + 0.1, h + 0.2), p.pt(u, v1 - 0.1, h + 0.2))


## A police barricade, folded flat and stood against a wall (the stack the
## yard keeps): the board striped white and blue with POLICE LINE on it, on its
## folded legs. n of them, one in front of another. Takes w by 0.5 of floor.
static func barricades(p: Node3D, b: int, u: float, v: float, yaw: float, n := 3, w := 1.8) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, w, 0.5)
	var white := Color(0.92, 0.92, 0.9)
	var blue := Color(0.16, 0.26, 0.6)
	for k in n:
		var one := Kit.group(g, Vector3(0.04 * k, 0, -0.16 + k * 0.12), Vector3(-9.0, 2.0 * k - 2.0, 0))
		Kit.box(one, Vector3(w, 0.24, 0.03), Vector3(0, 0.98, 0), white)
		var stripes := int(w / 0.32)
		for i in stripes:
			var x := -w * 0.5 + 0.16 + i * 0.32
			if absf(x) > 0.42:                   # the words' patch in the middle stays white
				Kit.box(one, Vector3(0.13, 0.24, 0.004), Vector3(x, 0.98, 0.017), blue, Vector3(0, 0, 0))
		Props.words(one, "POLICE LINE", Vector3(0, 0.98, 0.02), 0.1, blue)
		for s: float in [-1.0, 1.0]:
			Kit.box(one, Vector3(0.05, 1.1, 0.05), Vector3(s * (w * 0.5 - 0.22), 0.55, -0.03), Props.STEEL)
	return g


## A concrete jersey barrier 2 m long (yaw 0: along u): its broad foot, the
## narrower wall over it, a yellow line along its top, its edges chipped.
static func jersey(p: Node3D, b: int, u: float, v: float, yaw := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, yaw, 2.0, 0.62)
	var look := Kit.tex("sidewalk", 2.4, Color(0.62, 0.61, 0.58), true, Color(0.78, 0.77, 0.74))
	Kit.bevel_block(g, Vector3(2.0, 0.28, 0.62), Vector3.ZERO, look, 0.04)
	Kit.bevel_block(g, Vector3(2.0, 0.54, 0.3), Vector3(0, 0.27, 0), look, 0.04)
	Kit.box(g, Vector3(1.96, 0.06, 0.31), Vector3(0, 0.76, 0), SAFETY)
	var r := Props.rnd(u * 3.1 + v)
	Kit.box(g, Vector3(0.14, 0.08, 0.04), Vector3(-0.6 + r * 1.2, 0.79, 0.14), Color(0.5, 0.49, 0.47), Vector3(0, 0, 18))      # a chip out of its edge
	return g


## A sign wired to chain link (a fence along u at v, facing +v): a white plate
## with `text` on it in red, a little crooked.
static func fence_sign(p: Node3D, n: Node3D, u: float, v: float, text: String, w := 0.9, h := 0.5, y := 1.45) -> Node3D:
	var g := Kit.group(n, p.pt(u, v + 0.03))
	Kit.box(g, Vector3(w, h, 0.012), Vector3(0, y, 0), Props.PAPER, Vector3(0, 0, 2.5))
	Props.words(g, text, Vector3(0, y, 0.01), 0.11, Color(0.7, 0.1, 0.08)).rotation_degrees.z = 2.5
	for x: float in [-w * 0.42, w * 0.42]:       # its wires
		Kit.box(g, Vector3(0.012, 0.06, 0.02), Vector3(x, y + h * 0.4, -0.01), Props.STEEL)
	return g
