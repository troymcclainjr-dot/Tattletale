extends RefCounted
## Pen Lucy Precinct: a two-storey Baltimore neighborhood police station.
##
## Static exterior only, batched by the root-owned civic mesh kit: seven finishes
## (one draw surface each), one static body of main-volume colliders and two
## shaded labels. Local origin is the footprint centre at ground level (y = 0);
## the public front faces +Z. Every part, including the graded accessible walk
## and the rear service landing, stays inside the 24 m (X) by 20 m (Z)
## footprint. Built once; nothing here runs per frame or adds lights.
##
## Massing: a red-brown brick office block on a pale stone plinth, a projecting
## entrance pavilion with stone quoins and a recessed double entry, a raised
## attic over the public hall carrying the POLICE panel, a one-storey service
## wing (sally port) behind, inset on both sides, and a brick stair bulkhead,
## two packaged rooftop units, fans and a radio mast on the roofs.

const Kit := preload("res://scripts/city/city_civic_mesh_kit.gd")
const CityTheme := preload("res://scripts/city/city_theme.gd")

const FRONTAGE := 24.0
const DEPTH := 20.0

# Plan, metres. X is frontage, Z is depth, +Z is the street front.
const HX := 11.6          # half width of the two-storey block
const Z_F := 7.0          # wing wall face
const Z_P := 7.9          # entrance pavilion face
const Z_D := 6.2          # door line at the back of the recessed entry
const Z_B := -3.4         # back wall of the two-storey block
const PX := 3.9           # pavilion half width
const RX := 1.6           # recessed entry half width
const Z_RAISED := 1.6     # back wall of the raised hall behind the attic
const RZ := -9.7          # back wall of the service wing
const WX := 11.25         # service wing half width (inset 0.35 m per side)
const SKIN := 0.25        # brick skin thickness = window reveal depth
const APRON_EDGE := 9.98  # street edge of the entry walk

# Levels, metres above the surveyed ground.
const GRADE := -0.6       # plinths and skirts run below grade for slopes
const FLOOR := 0.12       # vestibule floor and door threshold (no steps)
const PLINTH := 0.95
const TABLE := 1.07       # top of the stone water table
const GF0 := 1.30         # ground-floor window glass
const GF1 := 3.40
const SIDE_SILL := 2.0    # high ground-floor windows on the side walls
const ENTRY_TOP := 3.50   # recessed entry opening head
const BELT0 := 4.78       # stone belt course, the upper sill line
const BELT1 := 4.95
const UF0 := 4.95         # upper-floor window glass
const UF1 := 6.75
const FRIEZE0 := 7.35
const FRIEZE1 := 7.70
const CORNICE := 7.90
const CAP := 8.00
const ROOF := 8.30        # main roof deck
const PARAPET := 8.78
const COPING := 8.90
const ATTIC_DECK := 9.55
const ATTIC := 9.90
const CREST := 10.30
const WING_ROOF := 4.55
const WING_PARAPET := 5.05
const PENTHOUSE_TOP := 10.85

# The walk falls 9 cm from the vestibule to the street edge: about 1:23.
const APRON_SLOPE := (0.12 - 0.03) / (9.98 - 7.9)
# Barlow Condensed capital height per em; signs are fitted to their panels.
const CAP_RATIO := 0.70

# Window bay centres: along X on each front wing (mirrored), along Z on the
# side walls, along X on the back wall above the service wing.
const FRONT_BAYS := [5.30, 7.62, 9.94]
const SIDE_BAYS := [4.85, 1.75, -1.35]
const BACK_BAYS := [-8.6, -5.4, 5.4, 8.6]
const CLERESTORY := [-8.6, -6.0, 0.4]
# Brick piers between the front bays (+X wing; mirrored) and the corner pier.
const FRONT_PIERS := [[3.9, 4.4], [6.19, 6.73], [8.51, 9.05]]
const CORNER_PIER := 10.84


static func footprint() -> Vector2:
	return Vector2(FRONTAGE, DEPTH)


static func build() -> Node3D:
	var kit: Kit = Kit.new("PenLucyPrecinct")
	# Seven finishes, seven draw surfaces. Colors follow the neighborhood
	# palette (brick_2, brick_dark, curb stone, sidewalk); weathering comes from
	# the shared city_surface kinds: 1 brick, 2 stone/concrete, 6 trim, 0 glass.
	kit.material("brick", Color("8a4a3a"), 1, 0.9)
	kit.material("brick_dark", Color("6e3a30"), 1, 0.9)
	kit.material("stone", Color("d2cbb8"), 2, 0.86)
	kit.material("paving", Color("9c998f"), 2, 0.92)
	kit.material("bronze", Color("3b352f"), 6, 0.85)
	kit.material("glass", Color("1b222b"), 0, 0.5)
	kit.material("blue", Color("27427a"), 6, 0.8)
	_front(kit)
	_entry(kit)
	_sides(kit)
	_back(kit)
	_fascia(kit)
	_service_wing(kit)
	_roofs(kit)
	_site(kit)
	_signs(kit)
	_colliders(kit)
	var root: Node3D = kit.finish()
	root.set_meta("footprint", footprint())
	root.set_meta("front_normal", Vector3(0.0, 0.0, 1.0))
	# Vestibule landing in front of the doors and the street end of the walk.
	root.set_meta("entrance", Vector3(0.0, FLOOR, Z_D + 0.8))
	root.set_meta("approach", Vector3(0.0, 0.03, APRON_EDGE - 0.4))
	return root


# --------------------------------------------------------------- helpers
## Wall frame: basis X runs along the facade (to the right seen from outside),
## Y is up, Z is the outward normal. Origin lies on the wall face at y = 0.
static func _frame(origin: Vector3, normal: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.UP.cross(normal), Vector3.UP, normal), origin)


## Box in wall-frame extents: u along the wall, absolute y, d out of the face.
static func _wb(kit: Kit, f: Transform3D, u0: float, u1: float, y0: float, y1: float, d0: float, d1: float, finish: String) -> void:
	var r: Vector3 = f.basis.x
	var n: Vector3 = f.basis.z
	var du := absf(u1 - u0)
	var dd := absf(d1 - d0)
	var center: Vector3 = f.origin + r * ((u0 + u1) * 0.5) + n * ((d0 + d1) * 0.5)
	center.y = (y0 + y1) * 0.5
	kit.box(center, Vector3(absf(r.x) * du + absf(n.x) * dd, absf(y1 - y0), absf(r.z) * du + absf(n.z) * dd), finish)


## Axis-aligned box from world extents (any order).
static func _bx(kit: Kit, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, finish: String) -> void:
	kit.box(Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5), Vector3(absf(x1 - x0), absf(y1 - y0), absf(z1 - z0)), finish)


static func _solid(kit: Kit, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float) -> void:
	kit.solid_box(Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5), Vector3(absf(x1 - x0), absf(y1 - y0), absf(z1 - z0)))


## Wall rectangle minus rectangular openings (Rect2 in u, y) as stacked boxes:
## horizontal bands between opening edges, merged upward while spans repeat.
static func _wall(kit: Kit, f: Transform3D, u0: float, u1: float, y0: float, y1: float, d0: float, d1: float, holes: Array[Rect2], finish: String) -> void:
	var levels: Array[float] = [y0, y1]
	for hole in holes:
		levels.append(clampf(hole.position.y, y0, y1))
		levels.append(clampf(hole.end.y, y0, y1))
	levels.sort()
	var bands: Array[float] = []
	for level in levels:
		if bands.is_empty() or level - bands[bands.size() - 1] > 0.001:
			bands.append(level)
	var active: Dictionary = {}
	for i in range(bands.size() - 1):
		var ya: float = bands[i]
		var yb: float = bands[i + 1]
		var mid := (ya + yb) * 0.5
		var cuts: Array[Vector2] = []
		for hole in holes:
			if hole.position.y < mid and hole.end.y > mid:
				cuts.append(Vector2(hole.position.x, hole.end.x))
		cuts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var spans: Array[Vector2] = []
		var cursor := u0
		for cut in cuts:
			if cut.x > cursor + 0.001:
				spans.append(Vector2(cursor, minf(cut.x, u1)))
			cursor = maxf(cursor, cut.y)
		if u1 > cursor + 0.001:
			spans.append(Vector2(cursor, u1))
		var carried: Dictionary = {}
		for span in spans:
			var key := "%d:%d" % [roundi(span.x * 1000.0), roundi(span.y * 1000.0)]
			if active.has(key):
				carried[key] = active[key]
				active.erase(key)
			else:
				carried[key] = Vector3(span.x, span.y, ya)
		for key in active:
			var done: Vector3 = active[key]
			_wb(kit, f, done.x, done.y, done.z, ya, d0, d1, finish)
		active = carried
	var top: float = bands[bands.size() - 1]
	for key in active:
		var done: Vector3 = active[key]
		_wb(kit, f, done.x, done.y, done.z, top, d0, d1, finish)


## Run of boxes along u that skips the given (sorted) u gaps.
static func _strip(kit: Kit, f: Transform3D, u0: float, u1: float, y0: float, y1: float, d0: float, d1: float, gaps: Array[Vector2], finish: String) -> void:
	var cursor := u0
	for gap in gaps:
		if gap.x > cursor:
			_wb(kit, f, cursor, gap.x, y0, y1, d0, d1, finish)
		cursor = maxf(cursor, gap.y)
	if u1 > cursor:
		_wb(kit, f, cursor, u1, y0, y1, d0, d1, finish)


## Dark glass set back in the reveal inside a bronze perimeter frame, with
## evenly spaced mullions and an optional transom bar (transom <= 0: none).
static func _glazing(kit: Kit, f: Transform3D, u0: float, u1: float, y0: float, y1: float, mullions: int, transom: float, back: float = -0.17) -> void:
	_wb(kit, f, u0, u1, y0, y1, back - 0.02, back, "glass")
	var d0 := back - 0.03
	var d1 := back + 0.05
	_wb(kit, f, u0, u1, y0, y0 + 0.07, d0, d1, "bronze")
	_wb(kit, f, u0, u1, y1 - 0.07, y1, d0, d1, "bronze")
	_wb(kit, f, u0, u0 + 0.07, y0 + 0.07, y1 - 0.07, d0, d1, "bronze")
	_wb(kit, f, u1 - 0.07, u1, y0 + 0.07, y1 - 0.07, d0, d1, "bronze")
	for i in range(1, mullions + 1):
		var mu := u0 + (u1 - u0) * float(i) / float(mullions + 1)
		_wb(kit, f, mu - 0.03, mu + 0.03, y0 + 0.07, y1 - 0.07, d0 + 0.01, d1 - 0.01, "bronze")
	if transom > 0.0:
		_wb(kit, f, u0 + 0.07, u1 - 0.07, transom - 0.035, transom + 0.035, d0 + 0.01, d1 - 0.01, "bronze")


## Opening (in u, y) a ground-floor window cuts, its stone sill included.
static func _ground_hole(u: float, half: float, y0: float, y1: float) -> Rect2:
	return Rect2(u - half, y0 - 0.12, half * 2.0, y1 - y0 + 0.12)


## Ground-floor office window: projecting stone sill, stone lintel with a
## keystone, mullion and transom, and a security grille inside the reveal.
static func _window_ground(kit: Kit, f: Transform3D, u: float, half: float, y0: float, y1: float) -> void:
	_glazing(kit, f, u - half, u + half, y0, y1, 1, y0 + (y1 - y0) * 0.68)
	_wb(kit, f, u - half - 0.12, u + half + 0.12, y0 - 0.12, y0, -0.17, 0.06, "stone")
	_wb(kit, f, u - half - 0.18, u + half + 0.18, y1, y1 + 0.30, 0.0, 0.03, "stone")
	_wb(kit, f, u - 0.15, u + 0.15, y1 - 0.04, y1 + 0.38, 0.0, 0.07, "stone")
	var bars := 4
	for i in bars:
		var bu := u - half + (float(i) + 0.5) * half * 2.0 / float(bars)
		_wb(kit, f, bu - 0.012, bu + 0.012, y0 + 0.02, y1 - 0.02, -0.082, -0.058, "bronze")
	# One grille rail, in line with the transom bar behind it.
	var rail := y0 + (y1 - y0) * 0.68
	_wb(kit, f, u - half, u + half, rail - 0.015, rail + 0.015, -0.085, -0.055, "bronze")


## High window (side walls, service wing): sill above head height of a
## passer-by, mullioned glass, a stone lintel, optionally with a keystone.
static func _window_high(kit: Kit, f: Transform3D, u: float, half: float, y0: float, y1: float, mullions: int, keystone: bool) -> void:
	_glazing(kit, f, u - half, u + half, y0, y1, mullions, -1.0)
	_wb(kit, f, u - half - 0.10, u + half + 0.10, y0 - 0.12, y0, -0.17, 0.06, "stone")
	_wb(kit, f, u - half - 0.15, u + half + 0.15, y1, y1 + 0.25, 0.0, 0.04, "stone")
	if keystone:
		_wb(kit, f, u - 0.15, u + 0.15, y1 - 0.04, y1 + 0.33, 0.0, 0.08, "stone")


## Opening an upper window cuts, its stone subsill included.
static func _upper_hole(u: float, half: float) -> Rect2:
	return Rect2(u - half, UF0 - 0.07, half * 2.0, UF1 - UF0 + 0.07)


## Upper-floor window on the belt course: stone subsill, flat stone lintel.
static func _window_upper(kit: Kit, f: Transform3D, u: float, half: float) -> void:
	_glazing(kit, f, u - half, u + half, UF0, UF1, 1, UF0 + (UF1 - UF0) * 0.70)
	_wb(kit, f, u - half, u + half, UF0 - 0.07, UF0, -0.17, 0.0, "stone")
	_wb(kit, f, u - half - 0.15, u + half + 0.15, UF1, UF1 + 0.25, 0.0, 0.03, "stone")


## Quad from four corners listed clockwise as seen from outside.
static func _quad(kit: Kit, a: Vector3, b: Vector3, c: Vector3, d: Vector3, finish: String) -> void:
	kit.triangle(a, b, c, finish)
	kit.triangle(a, c, d, finish)


## Corners of a slab whose top slopes along Z (top_z0 at z0, top_z1 at z1)
## over a flat bottom, ordered b00 b10 b11 b01 t00 t10 t11 t01; x0 < x1, z0 < z1.
static func _ramp_points(x0: float, x1: float, z0: float, z1: float, bottom: float, top_z0: float, top_z1: float) -> PackedVector3Array:
	return PackedVector3Array([Vector3(x0, bottom, z0), Vector3(x1, bottom, z0), Vector3(x1, bottom, z1), Vector3(x0, bottom, z1),
		Vector3(x0, top_z0, z0), Vector3(x1, top_z0, z0), Vector3(x1, top_z1, z1), Vector3(x0, top_z1, z1)])


## Sloped-top slab from triangles, all six faces wound outward.
static func _ramp(kit: Kit, x0: float, x1: float, z0: float, z1: float, bottom: float, top_z0: float, top_z1: float, finish: String) -> void:
	var p := _ramp_points(x0, x1, z0, z1, bottom, top_z0, top_z1)
	_quad(kit, p[4], p[5], p[6], p[7], finish)
	_quad(kit, p[0], p[3], p[2], p[1], finish)
	_quad(kit, p[7], p[6], p[2], p[3], finish)
	_quad(kit, p[5], p[4], p[0], p[1], finish)
	_quad(kit, p[6], p[5], p[1], p[2], finish)
	_quad(kit, p[4], p[7], p[3], p[0], finish)


## Faceted latitude/longitude sphere from kit triangles (flat shaded).
static func _sphere(kit: Kit, c: Vector3, r: float, finish: String, segments: int = 8, rings: int = 6) -> void:
	for i in rings:
		var a0 := PI * float(i) / float(rings)
		var a1 := PI * float(i + 1) / float(rings)
		for j in segments:
			var b0 := TAU * float(j) / float(segments)
			var b1 := TAU * float(j + 1) / float(segments)
			var p00 := c + r * Vector3(sin(a0) * cos(b0), cos(a0), sin(a0) * sin(b0))
			var p01 := c + r * Vector3(sin(a0) * cos(b1), cos(a0), sin(a0) * sin(b1))
			var p10 := c + r * Vector3(sin(a1) * cos(b0), cos(a1), sin(a1) * sin(b0))
			var p11 := c + r * Vector3(sin(a1) * cos(b1), cos(a1), sin(a1) * sin(b1))
			# The top ring's first and the bottom ring's second triangle collapse
			# onto a pole; skip those degenerate ones.
			if i > 0:
				kit.triangle(p01, p00, p10, finish)
			if i < rings - 1:
				kit.triangle(p01, p10, p11, finish)


## Round bar between two points (cylinder axis aligned by pitch, then yaw).
static func _strut(kit: Kit, a: Vector3, b: Vector3, radius: float, finish: String, sides: int = 6) -> void:
	var v := b - a
	var length := v.length()
	if length < 0.001:
		return
	var dir := v / length
	var pitch := acos(clampf(dir.y, -1.0, 1.0))
	var yaw := atan2(dir.x, dir.z)
	kit.cylinder((a + b) * 0.5, radius, length, finish, sides, -1.0, Vector3(pitch, yaw, 0.0))


## Shaded label fitted to a panel: capital height in metres, capped by width.
## Label3D centres the line box (ascent + descent), so it is lifted to centre
## the capitals on `at`. Faces +Z (yaw 0), single sided, kit font.
static func _sign(kit: Kit, text: String, at: Vector3, cap_height: float, max_width: float, color: Color) -> Label3D:
	var font: Font = CityTheme.T.body(700)
	var size := 96
	var pixel := cap_height / (CAP_RATIO * float(size))
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * pixel
	if width > max_width:
		pixel *= max_width / width
	var lift := (font.get_ascent(size) - font.get_descent(size) - CAP_RATIO * float(size)) * 0.5 * pixel
	var node: Label3D = kit.label(text, at + Vector3(0.0, lift, 0.0), size, pixel, color)
	node.shaded = true
	node.name = text.replace(" ", "") + "Sign"
	return node


static func _apron_y(z: float) -> float:
	return 0.03 + (APRON_EDGE - z) * APRON_SLOPE

# --------------------------------------------------------------- front
## Wings: three window bays each between brick piers, tall barred ground-floor
## windows with keystones, dark-brick spandrel panels, upper windows on the belt
## course. Pavilion: projecting 0.9 m, quoined corners, recessed entry below a
## stone-framed triple window between two narrow lights, attic above.
static func _front(kit: Kit) -> void:
	var wing := _frame(Vector3(0.0, 0.0, Z_F), Vector3(0.0, 0.0, 1.0))
	for s in [-1.0, 1.0]:
		var side: float = s
		var holes: Array[Rect2] = []
		for b in FRONT_BAYS:
			var x: float = side * float(b)
			holes.append(_ground_hole(x, 0.65, GF0, GF1))
			holes.append(Rect2(x - 0.6, 3.92, 1.2, 0.7))
			holes.append(_upper_hole(x, 0.6))
		_wall(kit, wing, minf(side * PX, side * HX), maxf(side * PX, side * HX), GRADE, PARAPET, -SKIN, 0.0, holes, "brick")
		for b in FRONT_BAYS:
			var x: float = side * float(b)
			_window_ground(kit, wing, x, 0.65, GF0, GF1)
			# Recessed dark-brick spandrel panel ties each bay's two windows.
			_wb(kit, wing, x - 0.6, x + 0.6, 3.92, 4.62, -SKIN, -0.04, "brick_dark")
			_window_upper(kit, wing, x, 0.6)
		for p in FRONT_PIERS:
			var pier: Array = p
			_wb(kit, wing, side * float(pier[0]), side * float(pier[1]), TABLE, FRIEZE0, 0.0, 0.10, "brick")
		# The corner pier wraps 0.9 m onto the side wall.
		_bx(kit, side * CORNER_PIER, side * (HX + 0.10), TABLE, FRIEZE0, Z_F - 0.8, Z_F + 0.10, "brick")

	var pav := _frame(Vector3(0.0, 0.0, Z_P), Vector3(0.0, 0.0, 1.0))
	var pav_holes: Array[Rect2] = [Rect2(-RX, -0.3, RX * 2.0, ENTRY_TOP + 0.3), Rect2(-1.65, BELT1, 3.3, 6.85 - BELT1)]
	for s in [-1.0, 1.0]:
		var side: float = s
		pav_holes.append(Rect2(side * 2.65 - 0.25, BELT1, 0.5, UF1 + 0.1 - BELT1))
	_wall(kit, pav, -PX, PX, GRADE, ATTIC, -SKIN, 0.0, pav_holes, "brick")
	for s in [-1.0, 1.0]:
		var side: float = s
		# Side returns from the wing face out to the pavilion face.
		_bx(kit, side * (PX - SKIN), side * PX, GRADE, ATTIC, Z_F - SKIN, Z_P - SKIN, "brick")
		# Narrow flanking lights with their own sills and lintels.
		var u := side * 2.65
		_glazing(kit, pav, u - 0.25, u + 0.25, BELT1 + 0.08, UF1 + 0.1, 0, 6.25)
		_wb(kit, pav, u - 0.33, u + 0.33, BELT1, BELT1 + 0.08, -0.17, 0.10, "stone")
		_wb(kit, pav, u - 0.36, u + 0.36, UF1 + 0.1, UF1 + 0.32, 0.0, 0.03, "stone")
	# Triple window over the entry: bronze mullions, stone architrave and sill,
	# a keystone block rising into the frieze.
	_glazing(kit, pav, -1.65, 1.65, BELT1 + 0.08, 6.85, 2, 6.25)
	_wb(kit, pav, -1.95, 1.95, BELT1, BELT1 + 0.08, -0.17, 0.16, "stone")
	_wb(kit, pav, -1.85, -1.65, BELT1 + 0.08, 7.05, 0.0, 0.08, "stone")
	_wb(kit, pav, 1.65, 1.85, BELT1 + 0.08, 7.05, 0.0, 0.08, "stone")
	_wb(kit, pav, -1.85, 1.85, 6.85, 7.05, 0.0, 0.08, "stone")
	_wb(kit, pav, -0.22, 0.22, 7.05, FRIEZE0, 0.0, 0.10, "stone")
	# Quoins: below the belt course and between it and the frieze.
	_quoins(kit, TABLE, BELT0, 8, 0)
	_quoins(kit, BELT1, FRIEZE0, 5, 0)


## Alternating long and short stone blocks wrapping both pavilion corners.
static func _quoins(kit: Kit, y0: float, y1: float, courses: int, start: int) -> void:
	var pitch := (y1 - y0) / float(courses)
	for k in courses:
		var long_course := (k + start) % 2 == 0
		var along_front := 0.50 if long_course else 0.30
		var along_side := 0.30 if long_course else 0.50
		var ya := y0 + float(k) * pitch + 0.02
		var yb := ya + pitch - 0.04
		for s in [-1.0, 1.0]:
			var side: float = s
			_bx(kit, side * (PX - along_front), side * (PX + 0.03), ya, yb, Z_P - along_side, Z_P + 0.03, "stone")


# --------------------------------------------------------------- entry
## Recessed vestibule 3.2 m wide and 1.7 m deep: stone-lined reveals, soffit
## with an unlit downlight, bronze storefront double doors with sidelights and
## transom, a flat stone floor flush with the graded walk. Outside: stone
## pilasters, the lettered entablature and a blue police globe each side.
static func _entry(kit: Kit) -> void:
	var lining := RX + 0.25
	for s in [-1.0, 1.0]:
		var side: float = s
		_bx(kit, side * (RX - 0.01), side * lining, FLOOR, ENTRY_TOP - 0.01, Z_D, Z_P, "stone")
	_bx(kit, -lining, lining, ENTRY_TOP - 0.01, ENTRY_TOP + 0.25, Z_D, Z_P, "stone")
	_bx(kit, -lining, lining, FLOOR, ENTRY_TOP - 0.01, Z_D - 0.2, Z_D, "stone")
	_bx(kit, -lining, lining, -0.3, FLOOR, Z_D, Z_P, "stone")
	# Downlight fixture, intercom plate on the east reveal, recessed mat.
	_bx(kit, -0.22, 0.22, ENTRY_TOP - 0.07, ENTRY_TOP - 0.01, Z_D + 0.65, Z_D + 0.95, "bronze")
	_bx(kit, -0.17, 0.17, ENTRY_TOP - 0.075, ENTRY_TOP - 0.07, Z_D + 0.70, Z_D + 0.90, "glass")
	_bx(kit, RX - 0.05, RX - 0.01, 1.05, 1.45, Z_D + 0.90, Z_D + 1.15, "bronze")
	_bx(kit, -0.95, 0.95, FLOOR, FLOOR + 0.012, Z_D + 0.20, Z_D + 1.00, "bronze")
	_doors(kit)
	var pav := _frame(Vector3(0.0, 0.0, Z_P), Vector3(0.0, 0.0, 1.0))
	for s in [-1.0, 1.0]:
		var side: float = s
		_wb(kit, pav, side * (RX - 0.01), side * 2.15, GRADE, ENTRY_TOP, 0.0, 0.07, "stone")
		_wb(kit, pav, side * 1.54, side * 2.22, GRADE, 0.60, 0.0, 0.11, "stone")
		_wb(kit, pav, side * 1.54, side * 2.22, 3.30, ENTRY_TOP, 0.0, 0.10, "stone")
		_lamp(kit, side * 2.65)
	# Entablature for PEN LUCY PRECINCT with a projecting cap.
	_wb(kit, pav, -2.40, 2.40, ENTRY_TOP, 4.40, 0.0, 0.10, "stone")
	_wb(kit, pav, -2.52, 2.52, 4.40, 4.52, 0.0, 0.16, "stone")


static func _doors(kit: Kit) -> void:
	var f := _frame(Vector3(0.0, 0.0, Z_D), Vector3(0.0, 0.0, 1.0))
	var head := 3.45
	var edge := RX - 0.01
	_wb(kit, f, -edge, -1.52, FLOOR, head, 0.0, 0.10, "bronze")
	_wb(kit, f, 1.52, edge, FLOOR, head, 0.0, 0.10, "bronze")
	_wb(kit, f, -1.52, 1.52, head - 0.08, head, 0.0, 0.10, "bronze")
	_wb(kit, f, -1.52, 1.52, 2.42, 2.52, 0.0, 0.10, "bronze")
	_wb(kit, f, -1.52, 1.52, 2.52, head - 0.08, 0.02, 0.04, "glass")
	for m in [-0.5, 0.5]:
		var mu: float = m
		_wb(kit, f, mu - 0.03, mu + 0.03, 2.52, head - 0.08, 0.0, 0.08, "bronze")
	_wb(kit, f, -0.97, 0.97, FLOOR, FLOOR + 0.015, 0.0, 0.16, "bronze")
	for s in [-1.0, 1.0]:
		var side: float = s
		# Sidelight over a kick panel, then the leaf: stiles, rails, glass, pull.
		_wb(kit, f, side * 0.97, side * 1.07, FLOOR, 2.42, 0.0, 0.10, "bronze")
		_wb(kit, f, side * 1.07, side * 1.52, 0.55, 2.42, 0.02, 0.04, "glass")
		_wb(kit, f, side * 1.07, side * 1.52, FLOOR, 0.55, 0.0, 0.06, "bronze")
		_wb(kit, f, 0.0, side * 0.11, FLOOR + 0.015, 2.42, 0.02, 0.08, "bronze")
		_wb(kit, f, side * 0.86, side * 0.97, FLOOR + 0.015, 2.42, 0.02, 0.08, "bronze")
		_wb(kit, f, side * 0.11, side * 0.86, 2.30, 2.42, 0.02, 0.08, "bronze")
		_wb(kit, f, side * 0.11, side * 0.86, FLOOR + 0.015, 0.40, 0.02, 0.08, "bronze")
		_wb(kit, f, side * 0.11, side * 0.86, 0.40, 2.30, 0.03, 0.05, "glass")
		_wb(kit, f, side * 0.16, side * 0.19, 0.95, 1.70, 0.08, 0.13, "bronze")


## Wall bracket carrying a blue police globe: painted, unlit, no emission.
static func _lamp(kit: Kit, x: float) -> void:
	var z := Z_P
	_bx(kit, x - 0.08, x + 0.08, 2.30, 2.95, z, z + 0.04, "bronze")
	_bx(kit, x - 0.025, x + 0.025, 2.58, 2.64, z + 0.04, z + 0.42, "bronze")
	_strut(kit, Vector3(x, 2.36, z + 0.04), Vector3(x, 2.60, z + 0.30), 0.016, "bronze")
	kit.cylinder(Vector3(x, 2.70, z + 0.38), 0.07, 0.12, "bronze", 6)
	_sphere(kit, Vector3(x, 2.95, z + 0.38), 0.2, "blue", 8, 5)
	kit.cylinder(Vector3(x, 3.17, z + 0.38), 0.075, 0.06, "bronze", 6)
	kit.cylinder(Vector3(x, 3.25, z + 0.38), 0.02, 0.10, "bronze", 6)

# --------------------------------------------------------------- sides, back
## Side elevations: the street front's bay rhythm, spandrel panels and upper
## windows, with high ground-floor windows (sill 2 m, no grille needed) for
## the offices and lockers behind, so either side can face the parking lot.
static func _sides(kit: Kit) -> void:
	for s in [-1.0, 1.0]:
		var side: float = s
		var f := _frame(Vector3(side * HX, 0.0, 0.0), Vector3(side, 0.0, 0.0))
		# Frame u runs along -Z on the east wall and along +Z on the west wall.
		var holes: Array[Rect2] = []
		for b in SIDE_BAYS:
			var u: float = -side * float(b)
			holes.append(_ground_hole(u, 0.65, SIDE_SILL, GF1))
			holes.append(Rect2(u - 0.6, 3.92, 1.2, 0.7))
			holes.append(_upper_hole(u, 0.6))
		var ua := -side * (Z_F - SKIN)
		var ub := -side * (Z_B + SKIN)
		_wall(kit, f, minf(ua, ub), maxf(ua, ub), GRADE, PARAPET, -SKIN, 0.0, holes, "brick")
		for b in SIDE_BAYS:
			var u: float = -side * float(b)
			_window_high(kit, f, u, 0.65, SIDE_SILL, GF1, 1, true)
			_wb(kit, f, u - 0.6, u + 0.6, 3.92, 4.62, -SKIN, -0.04, "brick_dark")
			_window_upper(kit, f, u, 0.6)


## Office block back wall: four upper windows over the service wing roof, a
## roof ladder and two leaders draining onto the wing roof.
static func _back(kit: Kit) -> void:
	var f := _frame(Vector3(0.0, 0.0, Z_B), Vector3(0.0, 0.0, -1.0))
	# Frame u = -x on the back wall.
	var holes: Array[Rect2] = []
	for b in BACK_BAYS:
		holes.append(_upper_hole(-float(b), 0.6))
	_wall(kit, f, -HX, HX, GRADE, PARAPET, -SKIN, 0.0, holes, "brick")
	for b in BACK_BAYS:
		_window_upper(kit, f, -float(b), 0.6)
	for s in [-1.0, 1.0]:
		var side: float = s
		_downspout(kit, side * 10.5, Z_B - 0.20, WING_ROOF + 0.05, 7.0, -1.0)
		_bx(kit, side * 10.25, side * 10.75, WING_ROOF, WING_ROOF + 0.05, Z_B - 0.85, Z_B - 0.05, "paving")
	_ladder(kit, 9.9)


## Square bronze leader with a conductor head and a kick-out shoe; `out`
## (+1 or -1) is the Z direction away from the wall.
static func _downspout(kit: Kit, x: float, z: float, y0: float, y1: float, out: float) -> void:
	_bx(kit, x - 0.06, x + 0.06, y0 + 0.12, y1, z - 0.06, z + 0.06, "bronze")
	_bx(kit, x - 0.13, x + 0.13, y1, y1 + 0.28, z - 0.11, z + 0.11, "bronze")
	_bx(kit, x - 0.06, x + 0.06, y0, y0 + 0.14, z - 0.06 + out * 0.06, z + 0.06 + out * 0.06, "bronze")


## Open rung ladder from the service wing roof, over the coping, to the main roof.
static func _ladder(kit: Kit, x: float) -> void:
	var z := Z_B - 0.45
	var top := COPING + 0.95
	for s in [-0.22, 0.22]:
		var rx: float = x + float(s)
		_bx(kit, rx - 0.025, rx + 0.025, WING_ROOF, top, z - 0.025, z + 0.025, "bronze")
		_bx(kit, rx - 0.025, rx + 0.025, top - 0.05, top, z, Z_B + SKIN + 0.3, "bronze")
		_bx(kit, rx - 0.025, rx + 0.025, ROOF, top - 0.05, Z_B + SKIN + 0.25, Z_B + SKIN + 0.3, "bronze")
		_bx(kit, rx - 0.02, rx + 0.02, 6.38, 6.42, z, Z_B, "bronze")
	var rung := WING_ROOF + 0.3
	while rung < COPING + 0.7:
		_bx(kit, x - 0.22, x + 0.22, rung - 0.015, rung + 0.015, z - 0.015, z + 0.015, "bronze")
		rung += 0.35


# --------------------------------------------------------------- fascia
## Continuous stone courses around the office block and pavilion (plinth,
## water table, belt, frieze, cornice and its cap), modillions under the
## street cornice and coping on the wing parapets.
static func _fascia(kit: Kit) -> void:
	_ring(kit, GRADE, PLINTH, 0.06, 2.15, false)
	_ring(kit, PLINTH, TABLE, 0.10, 2.15, false)
	_ring(kit, BELT0, BELT1, 0.13, 0.0, true)
	_ring(kit, FRIEZE0, FRIEZE1, 0.12, 0.0, true)
	_ring(kit, FRIEZE1, CORNICE, 0.30, 0.0, true)
	_ring(kit, CORNICE, CAP, 0.36, 0.0, true)
	for s in [-1.0, 1.0]:
		var side: float = s
		for i in 9:
			var x := lerpf(PX + 0.45, HX - 0.45, float(i) / 8.0)
			_bx(kit, side * (x - 0.06), side * (x + 0.06), 7.56, FRIEZE1, Z_F + 0.12, Z_F + 0.26, "stone")
	for i in 9:
		var x := lerpf(-PX + 0.35, PX - 0.35, float(i) / 8.0)
		_bx(kit, x - 0.06, x + 0.06, 7.56, FRIEZE1, Z_P + 0.12, Z_P + 0.26, "stone")
	var inner := SKIN + 0.05
	for s in [-1.0, 1.0]:
		var side: float = s
		_bx(kit, side * PX, side * (HX + 0.05), PARAPET, COPING, Z_F - inner, Z_F + 0.05, "stone")
		_bx(kit, side * (HX - inner), side * (HX + 0.05), PARAPET, COPING, Z_B - 0.05, Z_F - inner, "stone")
	_bx(kit, -(HX - inner), HX - inner, PARAPET, COPING, Z_B - 0.05, Z_B + inner, "stone")


## One stone course around the office block outline: both wing fronts, the
## pavilion returns and front, the side walls and optionally the back wall.
## `o` is its projection. entry_gap > 0 leaves the recessed entry and its
## pilasters free; without the back wall, the strips of the office block's
## back face beside the inset service wing are dressed instead.
static func _ring(kit: Kit, y0: float, y1: float, o: float, entry_gap: float, back: bool) -> void:
	var e := 0.02
	for s in [-1.0, 1.0]:
		var side: float = s
		_bx(kit, side * (PX + o), side * (HX + o), y0, y1, Z_F - e, Z_F + o, "stone")
		_bx(kit, side * (PX - e), side * (PX + o), y0, y1, Z_F - e, Z_P - e, "stone")
		_bx(kit, side * (HX - e), side * (HX + o), y0, y1, Z_B - o, Z_F - e, "stone")
		if entry_gap > 0.0:
			_bx(kit, side * entry_gap, side * (PX + o), y0, y1, Z_P - e, Z_P + o, "stone")
		if not back:
			_bx(kit, side * WX, side * (HX - e), y0, y1, Z_B - o, Z_B + e, "stone")
	if entry_gap <= 0.0:
		_bx(kit, -(PX + o), PX + o, y0, y1, Z_P - e, Z_P + o, "stone")
	if back:
		_bx(kit, -(HX - e), HX - e, y0, y1, Z_B - o, Z_B + e, "stone")


# --------------------------------------------------------------- service wing
## One-storey sally port and service wing in darker brick, inset 0.35 m each
## side: overhead door with guards, steel staff door under a canopy on a flat
## landing, and a ribbon of three-light clerestory windows on three sides.
static func _service_wing(kit: Kit) -> void:
	var back := _frame(Vector3(0.0, 0.0, RZ), Vector3(0.0, 0.0, -1.0))
	# Frame u = -x: the overhead door spans x 3.8..7.4, the staff door x -3.55..-2.45.
	var garage := Vector2(-7.4, -3.8)
	var door := Vector2(2.45, 3.55)
	var holes: Array[Rect2] = [Rect2(garage.x, 0.0, garage.y - garage.x, 3.3), Rect2(door.x, FLOOR, door.y - door.x, 2.35 - FLOOR)]
	for c in CLERESTORY:
		holes.append(_ground_hole(-float(c), 0.7, 2.55, 3.55))
	_wall(kit, back, -WX, WX, GRADE, WING_PARAPET, -SKIN, 0.0, holes, "brick_dark")
	for c in CLERESTORY:
		_window_high(kit, back, -float(c), 0.7, 2.55, 3.55, 2, false)
	# Overhead door: curtain 13 cm back with ribs, bottom seal, lintel, guards.
	_wb(kit, back, garage.x, garage.y, 0.0, 3.3, -0.19, -0.13, "stone")
	for k in 6:
		var ry := 0.42 + float(k) * 0.5
		_wb(kit, back, garage.x, garage.y, ry, ry + 0.05, -0.13, -0.11, "stone")
	_wb(kit, back, garage.x, garage.y, 0.0, 0.08, -0.13, -0.10, "bronze")
	_wb(kit, back, garage.x - 0.2, garage.y + 0.2, 3.3, 3.62, 0.0, 0.05, "stone")
	for g in [garage.x, garage.y - 0.08]:
		var gu: float = g
		_wb(kit, back, gu, gu + 0.08, 0.0, 1.1, -0.13, 0.0, "bronze")
	_wb(kit, back, -5.75, -5.45, 3.78, 4.02, 0.0, 0.14, "bronze")
	_wb(kit, back, -5.70, -5.50, 3.77, 3.78, 0.02, 0.12, "glass")
	# Staff door: grey steel leaf in a bronze frame, canopy, wall light, landing.
	_wb(kit, back, door.x + 0.08, door.y - 0.08, FLOOR, 2.27, -0.13, -0.10, "stone")
	_wb(kit, back, door.x, door.x + 0.08, FLOOR, 2.35, -0.14, -0.08, "bronze")
	_wb(kit, back, door.y - 0.08, door.y, FLOOR, 2.35, -0.14, -0.08, "bronze")
	_wb(kit, back, door.x, door.y, 2.27, 2.35, -0.14, -0.08, "bronze")
	_wb(kit, back, door.x + 0.14, door.x + 0.18, 1.0, 1.12, -0.10, -0.06, "bronze")
	_wb(kit, back, door.x - 0.25, door.y + 0.25, 2.62, 2.72, 0.0, 0.28, "stone")
	_wb(kit, back, door.x + 0.40, door.y - 0.40, 2.85, 3.10, 0.0, 0.12, "bronze")
	_wb(kit, back, door.x + 0.45, door.y - 0.45, 2.84, 2.85, 0.02, 0.10, "glass")
	_wb(kit, back, door.x - 0.3, door.y + 0.3, -0.3, FLOOR, 0.0, 0.28, "stone")
	for s in [-1.0, 1.0]:
		var side: float = s
		var f := _frame(Vector3(side * WX, 0.0, 0.0), Vector3(side, 0.0, 0.0))
		var u := side * 6.5
		var side_holes: Array[Rect2] = [_ground_hole(u, 0.7, 2.55, 3.55)]
		var ua := -side * (RZ + SKIN)
		var ub := -side * Z_B
		_wall(kit, f, minf(ua, ub), maxf(ua, ub), GRADE, WING_PARAPET, -SKIN, 0.0, side_holes, "brick_dark")
		_window_high(kit, f, u, 0.7, 2.55, 3.55, 2, false)
		_downspout(kit, side * 10.75, RZ - 0.17, 0.02, WING_ROOF + 0.05, -1.0)
		_bx(kit, side * 10.67, side * 10.83, WING_ROOF + 0.10, WING_ROOF + 0.22, RZ - 0.11, RZ + SKIN, "bronze")
	_bx(kit, -(WX - SKIN), WX - SKIN, WING_ROOF - 0.2, WING_ROOF, RZ + SKIN, Z_B, "paving")
	var inner := SKIN + 0.05
	_bx(kit, -(WX + 0.05), WX + 0.05, WING_PARAPET, WING_PARAPET + 0.12, RZ - 0.05, RZ + inner, "stone")
	for s in [-1.0, 1.0]:
		var side: float = s
		_bx(kit, side * (WX - inner), side * (WX + 0.05), WING_PARAPET, WING_PARAPET + 0.12, RZ + inner, Z_B, "stone")
	_wing_band(kit, GRADE, PLINTH, 0.06, garage, door)
	_wing_band(kit, PLINTH, TABLE, 0.10, garage, door)


static func _wing_band(kit: Kit, y0: float, y1: float, o: float, garage: Vector2, door: Vector2) -> void:
	var back := _frame(Vector3(0.0, 0.0, RZ), Vector3(0.0, 0.0, -1.0))
	var gaps: Array[Vector2] = [garage, door]
	_strip(kit, back, -(WX + o), WX + o, y0, y1, -0.02, o, gaps, "stone")
	for s in [-1.0, 1.0]:
		var side: float = s
		_bx(kit, side * (WX - 0.02), side * (WX + o), y0, y1, RZ + 0.02, Z_B, "stone")

# --------------------------------------------------------------- roofs
## Roof silhouette, stepping up from the service wing (5.2 m) over the office
## parapets (8.9 m) to the raised hall and crest (10.4 m), the stair bulkhead
## (11 m) and the radio mast. Equipment is chunky enough to read over the
## parapets from the street and in detail from above.
static func _roofs(kit: Kit) -> void:
	_bx(kit, -(HX - SKIN), HX - SKIN, ROOF - 0.2, ROOF, Z_B + SKIN, Z_F - SKIN, "paving")
	# Raised public hall behind the attic: side walls over the wing roofs, back
	# wall, deck and coping; a stepped crest with a blank datestone.
	for s in [-1.0, 1.0]:
		var side: float = s
		_bx(kit, side * (PX - SKIN), side * PX, ROOF, ATTIC, Z_RAISED, Z_F - SKIN, "brick")
		_bx(kit, side * (PX - SKIN - 0.05), side * (PX + 0.05), ATTIC, ATTIC + 0.12, Z_RAISED - 0.05, Z_P - SKIN - 0.05, "stone")
	_bx(kit, -(PX - SKIN), PX - SKIN, ROOF, ATTIC, Z_RAISED, Z_RAISED + SKIN, "brick")
	_bx(kit, -(PX - SKIN), PX - SKIN, ATTIC_DECK - 0.2, ATTIC_DECK, Z_RAISED + SKIN, Z_P - SKIN, "paving")
	_bx(kit, -(PX + 0.05), PX + 0.05, ATTIC, ATTIC + 0.12, Z_P - SKIN - 0.05, Z_P + 0.05, "stone")
	_bx(kit, -(PX - SKIN - 0.05), PX - SKIN - 0.05, ATTIC, ATTIC + 0.12, Z_RAISED - 0.05, Z_RAISED + SKIN + 0.05, "stone")
	_bx(kit, -1.6, 1.6, ATTIC + 0.12, CREST, Z_P - 0.6, Z_P, "brick")
	_bx(kit, -1.65, 1.65, CREST, CREST + 0.12, Z_P - 0.65, Z_P + 0.05, "stone")
	_bx(kit, -0.55, 0.55, ATTIC + 0.2, CREST - 0.07, Z_P, Z_P + 0.03, "stone")
	_penthouse(kit)
	_rtu(kit, -9.4, 1.7, ROOF, 2.4, 1.25, 1.8)
	_rtu(kit, 7.8, -0.5, ROOF, 2.8, 1.15, 1.8)
	# Conduit run from the west unit to the bulkhead, raised on the roof.
	_bx(kit, -8.2, -6.94, ROOF, ROOF + 0.10, 1.15, 1.25, "bronze")
	_bx(kit, -7.04, -6.94, ROOF, ROOF + 0.10, 0.2, 1.15, "bronze")
	_exhaust_fan(kit, 1.9, ATTIC_DECK, 3.6)
	_vent(kit, -2.6, ROOF, -2.2)
	_vent(kit, -10.4, ROOF, 5.2)
	# Roof hatch.
	_bx(kit, 5.12, 6.08, ROOF, ROOF + 0.4, 3.92, 4.88, "stone")
	_bx(kit, 5.07, 6.13, ROOF + 0.4, ROOF + 0.45, 3.87, 4.93, "bronze")
	# Service wing roof: condenser with its line set, sally port skylight,
	# exhaust fan and vents.
	_bx(kit, -8.6, -7.4, WING_ROOF, WING_ROOF + 0.1, -7.2, -6.0, "paving")
	_bx(kit, -8.5, -7.5, WING_ROOF + 0.1, WING_ROOF + 0.9, -7.1, -6.1, "stone")
	kit.cylinder(Vector3(-8.0, WING_ROOF + 0.93, -6.6), 0.34, 0.06, "bronze", 10)
	kit.cylinder(Vector3(-8.0, WING_ROOF + 0.965, -6.6), 0.28, 0.012, "glass", 10)
	_bx(kit, -7.62, -7.56, WING_ROOF, WING_ROOF + 0.06, -6.1, Z_B - 0.02, "bronze")
	_bx(kit, -7.62, -7.56, WING_ROOF, BELT0 - 0.06, Z_B - 0.08, Z_B - 0.02, "bronze")
	_bx(kit, 5.0, 6.4, WING_ROOF, WING_ROOF + 0.3, -7.3, -5.9, "stone")
	_bx(kit, 5.06, 6.34, WING_ROOF + 0.3, WING_ROOF + 0.42, -7.24, -5.96, "glass")
	_exhaust_fan(kit, 1.5, WING_ROOF, -7.2)
	_vent(kit, -3.0, WING_ROOF, -5.0)


## Brick stair bulkhead: grey steel door under a canopy, louvre facing the
## street, coping and deck, and the precinct's radio mast with a dish.
static func _penthouse(kit: Kit) -> void:
	var x0 := -7.6
	var x1 := -4.4
	var z0 := -3.0
	var z1 := 0.2
	var top := PENTHOUSE_TOP
	_bx(kit, x0, x1, ROOF, top, z0, z1, "brick_dark")
	_bx(kit, x0 - 0.06, x1 + 0.06, top, top + 0.12, z1 - 0.3, z1 + 0.06, "stone")
	_bx(kit, x0 - 0.06, x1 + 0.06, top, top + 0.12, z0 - 0.06, z0 + 0.3, "stone")
	_bx(kit, x0 - 0.06, x0 + 0.3, top, top + 0.12, z0 + 0.3, z1 - 0.3, "stone")
	_bx(kit, x1 - 0.3, x1 + 0.06, top, top + 0.12, z0 + 0.3, z1 - 0.3, "stone")
	_bx(kit, x0 + 0.3, x1 - 0.3, top, top + 0.03, z0 + 0.3, z1 - 0.3, "paving")
	# East face: frame u = -z, the door spans z -1.95..-0.95.
	var east := _frame(Vector3(x1, 0.0, 0.0), Vector3(1.0, 0.0, 0.0))
	_wb(kit, east, 0.95, 1.95, ROOF + 0.02, ROOF + 2.17, 0.0, 0.035, "stone")
	_wb(kit, east, 0.87, 0.95, ROOF, ROOF + 2.25, 0.0, 0.06, "bronze")
	_wb(kit, east, 1.95, 2.03, ROOF, ROOF + 2.25, 0.0, 0.06, "bronze")
	_wb(kit, east, 0.87, 2.03, ROOF + 2.17, ROOF + 2.25, 0.0, 0.06, "bronze")
	_wb(kit, east, 1.05, 1.09, ROOF + 1.0, ROOF + 1.12, 0.035, 0.07, "bronze")
	_wb(kit, east, 0.75, 2.15, ROOF + 2.36, ROOF + 2.44, 0.0, 0.5, "stone")
	# Street face: louvre bank over a dark backing.
	var south := _frame(Vector3(0.0, 0.0, z1), Vector3(0.0, 0.0, 1.0))
	_wb(kit, south, -6.6, -5.4, 9.3, 10.3, 0.0, 0.01, "glass")
	_wb(kit, south, -6.66, -5.34, 9.24, 9.3, 0.0, 0.06, "bronze")
	_wb(kit, south, -6.66, -5.34, 10.3, 10.36, 0.0, 0.06, "bronze")
	_wb(kit, south, -6.66, -6.6, 9.3, 10.3, 0.0, 0.06, "bronze")
	_wb(kit, south, -5.4, -5.34, 9.3, 10.3, 0.0, 0.06, "bronze")
	for k in 4:
		var ly := 9.38 + float(k) * 0.23
		_wb(kit, south, -6.6, -5.4, ly, ly + 0.09, 0.01, 0.05, "bronze")
	# Radio mast on a base plate: crossarm with two whips, top whip, dish.
	var mast := Vector3(-5.3, top + 0.03, -2.0)
	_bx(kit, mast.x - 0.22, mast.x + 0.22, mast.y, mast.y + 0.06, mast.z - 0.22, mast.z + 0.22, "bronze")
	kit.cylinder(mast + Vector3(0.0, 2.95, 0.0), 0.075, 5.8, "bronze", 8, 0.045)
	var arm := mast.y + 5.0
	_bx(kit, mast.x - 0.7, mast.x + 0.7, arm - 0.03, arm + 0.03, mast.z - 0.03, mast.z + 0.03, "bronze")
	for s in [-1.0, 1.0]:
		kit.cylinder(Vector3(mast.x + float(s) * 0.68, arm + 0.85, mast.z), 0.02, 1.7, "bronze", 4)
	kit.cylinder(mast + Vector3(0.0, 6.4, 0.0), 0.015, 1.2, "bronze", 4)
	_bx(kit, mast.x - 0.02, mast.x + 0.02, mast.y + 2.57, mast.y + 2.63, mast.z, mast.z + 0.2, "bronze")
	kit.cylinder(mast + Vector3(0.0, 2.6, 0.26), 0.06, 0.18, "stone", 12, 0.42, Vector3(deg_to_rad(60.0), 0.0, 0.0))


## Packaged rooftop unit on a curb: casing, louvre bank and access panel
## handle on both long faces, two condenser fan shrouds, an end flue hood.
static func _rtu(kit: Kit, cx: float, cz: float, deck: float, sx: float, sy: float, sz: float) -> void:
	var hx := sx * 0.5
	var hz := sz * 0.5
	_bx(kit, cx - hx - 0.1, cx + hx + 0.1, deck, deck + 0.25, cz - hz - 0.1, cz + hz + 0.1, "paving")
	var y0 := deck + 0.25
	_bx(kit, cx - hx, cx + hx, y0, y0 + sy, cz - hz, cz + hz, "stone")
	for s in [-1.0, 1.0]:
		var side: float = s
		var face := cz + side * hz
		for k in 4:
			var ly := y0 + 0.22 + float(k) * 0.2
			_bx(kit, cx - hx + 0.12, cx + 0.1, ly, ly + 0.08, face, face + side * 0.03, "bronze")
		var fx := cx + side * sx * 0.25
		kit.cylinder(Vector3(fx, y0 + sy + 0.06, cz), 0.36, 0.12, "bronze", 8)
		kit.cylinder(Vector3(fx, y0 + sy + 0.125, cz), 0.29, 0.012, "glass", 8)
	_bx(kit, cx + hx, cx + hx + 0.3, y0 + 0.35, y0 + 0.8, cz - 0.3, cz + 0.3, "stone")


## Mushroom exhaust fan on a curb.
static func _exhaust_fan(kit: Kit, x: float, deck: float, z: float) -> void:
	_bx(kit, x - 0.42, x + 0.42, deck, deck + 0.3, z - 0.42, z + 0.42, "paving")
	kit.cylinder(Vector3(x, deck + 0.42, z), 0.27, 0.24, "stone", 8)
	kit.cylinder(Vector3(x, deck + 0.66, z), 0.48, 0.24, "stone", 8, 0.16)
	kit.cylinder(Vector3(x, deck + 0.80, z), 0.16, 0.04, "stone", 8)


## Plumbing vent stack with a cap.
static func _vent(kit: Kit, x: float, deck: float, z: float) -> void:
	kit.cylinder(Vector3(x, deck + 0.3, z), 0.06, 0.6, "bronze", 6)
	kit.cylinder(Vector3(x, deck + 0.64, z), 0.1, 0.08, "bronze", 6)

# --------------------------------------------------------------- site
## Entry walk graded about 1:23 from the street edge up to the flush vestibule
## floor (no steps, no handrails needed), a stone street edge, security
## bollards with blue reflector bands, a flagpole on a stone base, corner
## cameras and two guard bollards at the overhead door. No parking lot: that
## is the root's separate site integration.
static func _site(kit: Kit) -> void:
	var edge := APRON_EDGE - 0.25
	_ramp(kit, -HX, HX, Z_P, edge, -0.3, FLOOR, _apron_y(edge), "paving")
	_ramp(kit, -HX, HX, edge, APRON_EDGE, -0.3, _apron_y(edge), _apron_y(APRON_EDGE), "stone")
	kit.solid_convex(_ramp_points(-HX, HX, Z_P, APRON_EDGE, -0.3, FLOOR, _apron_y(APRON_EDGE)))
	for s in [-1.0, 1.0]:
		var side: float = s
		var x0 := minf(side * PX, side * HX)
		var x1 := maxf(side * PX, side * HX)
		_ramp(kit, x0, x1, Z_F, Z_P, -0.3, _apron_y(Z_F), FLOOR, "paving")
		kit.solid_convex(_ramp_points(x0, x1, Z_F, Z_P, -0.3, _apron_y(Z_F), FLOOR))
	for b in [-3.3, -1.3, 1.3, 3.3]:
		var x: float = b
		_bollard(kit, x, 9.35, _apron_y(9.35), 0.11, true)
	# Flagpole on the axis of the west wing's middle bay.
	var fx: float = -float(FRONT_BAYS[1])
	var fz := 8.95
	var fy := _apron_y(fz)
	_bx(kit, fx - 0.45, fx + 0.45, fy - 0.15, fy + 0.30, fz - 0.45, fz + 0.45, "stone")
	_bx(kit, fx - 0.36, fx + 0.36, fy + 0.30, fy + 0.40, fz - 0.36, fz + 0.36, "stone")
	kit.cylinder(Vector3(fx, fy + 4.9, fz), 0.07, 9.0, "bronze", 8, 0.04)
	_sphere(kit, Vector3(fx, fy + 9.47, fz), 0.09, "stone", 6, 4)
	_bx(kit, fx - 0.02, fx + 0.02, 1.25, 1.45, fz + 0.07, fz + 0.11, "bronze")
	_bx(kit, fx - 0.006, fx + 0.006, 1.40, fy + 9.36, fz + 0.08, fz + 0.092, "bronze")
	_solid(kit, fx - 0.45, fx + 0.45, fy - 0.15, fy + 0.40, fz - 0.45, fz + 0.45)
	_solid(kit, fx - 0.08, fx + 0.08, fy + 0.40, fy + 9.40, fz - 0.08, fz + 0.08)
	# Security cameras on the front corner piers, turned toward the entry.
	for s in [-1.0, 1.0]:
		var side: float = s
		var cx := side * (HX - 0.35)
		_bx(kit, cx - 0.04, cx + 0.04, 4.28, 4.36, Z_F + 0.10, Z_F + 0.32, "bronze")
		kit.box(Vector3(cx - side * 0.05, 4.24, Z_F + 0.40), Vector3(0.12, 0.11, 0.26), "bronze", -side * 0.5)
	# Guard bollards either side of the overhead door, clear of the water table.
	for b in [3.55, 7.65]:
		var x: float = b
		_bollard(kit, x, RZ - 0.19, 0.0, 0.09, false)


## Slightly tapered bronze bollard, optionally with a blue reflector band; solid.
static func _bollard(kit: Kit, x: float, z: float, base: float, radius: float, band: bool) -> void:
	kit.cylinder(Vector3(x, base + 0.43, z), radius, 0.95, "bronze", 8, radius - 0.015)
	if band:
		kit.cylinder(Vector3(x, base + 0.72, z), radius + 0.005, 0.07, "blue", 8)
	_solid(kit, x - radius - 0.01, x + radius + 0.01, base - 0.05, base + 0.96, z - radius - 0.01, z + radius + 0.01)


# --------------------------------------------------------------- signs
## POLICE in cream capitals on the blue attic panel (stone frame), and PEN LUCY
## PRECINCT in dark bronze capitals on the stone entablature over the entry.
static func _signs(kit: Kit) -> void:
	_bx(kit, -2.55, 2.55, 8.30, 9.62, Z_P, Z_P + 0.025, "blue")
	_bx(kit, -2.69, 2.69, 9.62, 9.76, Z_P, Z_P + 0.06, "stone")
	_bx(kit, -2.69, 2.69, 8.16, 8.30, Z_P, Z_P + 0.06, "stone")
	_bx(kit, -2.69, -2.55, 8.30, 9.62, Z_P, Z_P + 0.06, "stone")
	_bx(kit, 2.55, 2.69, 8.30, 9.62, Z_P, Z_P + 0.06, "stone")
	_sign(kit, "POLICE", Vector3(0.0, 8.96, Z_P + 0.045), 0.78, 4.5, Color("efe8d6"))
	_sign(kit, "PEN LUCY PRECINCT", Vector3(0.0, 3.95, Z_P + 0.115), 0.31, 4.3, Color("2b2925"))


# --------------------------------------------------------------- collision
## Main volumes only; trim stays visual. The office block runs to its coping,
## carved around the open vestibule (floor and head kept solid); then the
## raised hall, the service wing, the bulkhead, the two rooftop units and the
## staff door landing. The walk, bollards and flagpole add theirs in _site.
static func _colliders(kit: Kit) -> void:
	_solid(kit, -HX, HX, -0.3, COPING, Z_B, Z_D)
	_solid(kit, -HX, -RX, -0.3, COPING, Z_D, Z_F)
	_solid(kit, RX, HX, -0.3, COPING, Z_D, Z_F)
	_solid(kit, -PX, -RX, -0.3, COPING, Z_F, Z_P)
	_solid(kit, RX, PX, -0.3, COPING, Z_F, Z_P)
	_solid(kit, -RX, RX, ENTRY_TOP - 0.01, COPING, Z_D, Z_P)
	_solid(kit, -RX, RX, -0.3, FLOOR, Z_D, Z_P)
	_solid(kit, -PX, PX, COPING, ATTIC + 0.12, Z_RAISED, Z_P)
	_solid(kit, -WX, WX, -0.3, WING_PARAPET + 0.12, RZ, Z_B)
	_solid(kit, -7.6, -4.4, COPING, PENTHOUSE_TOP + 0.12, -3.0, 0.2)
	_solid(kit, -10.6, -8.2, COPING, ROOF + 1.5, 0.8, 2.6)
	_solid(kit, 6.4, 9.2, COPING, ROOF + 1.4, -1.4, 0.4)
	_solid(kit, -3.85, -2.15, -0.3, FLOOR, RZ - 0.28, RZ)
