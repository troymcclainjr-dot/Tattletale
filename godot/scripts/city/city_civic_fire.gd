extends RefCounted
## East 39th engine house: a compact two-bay Baltimore brick firehouse.
## Local origin at the footprint center on finished floor Y=0; FRONT faces +Z.
## The hose tower and office wing hold the street corner on local -X.
## Static exterior only: the shared civic kit batches every finish into one
## surface and gathers the main masses into one static body.
const Kit = preload("res://scripts/city/city_civic_mesh_kit.gd")

# Facade sides for the slab helpers. Offsets are measured outward from a wall
# plane, so a positive offset always projects toward the street side.
const FRONT := 0
const BACK := 1
const RIGHT := 2
const LEFT := 3

# Datums shared by every volume: base course, belt over the apparatus doors,
# second-floor sill course and second-floor window heads.
const BASE_TOP := 0.55
const BELT_BOTTOM := 4.3
const BELT_TOP := 4.75
const SILL_BOTTOM := 5.75
const SILL_TOP := 5.9
const UPPER_HEAD := 7.6
const INK := Color("2b201b")

# Window centers along each facade.
const UPPER_FRONT := [-2.2, -0.4, 3.4, 5.2, 7.55]
const SIDE_BAYS := [2.3, -0.2, -2.7]
const REAR_BAYS := [-2.6, 0.4, 3.4, 6.4]
const OFFICE_BAYS := [-6.6, -3.95, -1.3]
const ANNEX_BAYS := [-2.6, 0.9, 4.4]


static func footprint() -> Vector2:
	return Vector2(18.0, 17.0)


static func build() -> Node3D:
	var k := Kit.new("EngineHouse")
	_palette(k)
	_apparatus_block(k)
	_bay_door(k, -3.4, 0.8)
	_bay_door(k, 2.2, 6.4)
	_hose_tower(k)
	_personnel_entry(k)
	_office_wing(k)
	_rear_annex(k)
	_forecourt(k)
	_roof_equipment(k)
	var root: Node3D = k.finish()
	root.set_meta("civic_type", "fire")
	root.set_meta("footprint_m", footprint())
	root.set_meta("front_local", Vector3(0, 0, 1))
	root.set_meta("ground_y", 0.0)
	root.set_meta("storeys", 2)
	# Walkable apparatus apron (x, z, width, depth): visual paving, no collision.
	root.set_meta("apron_local_xz", Rect2(-4.8, 3.6, 13.8, 4.9))
	_marker(root, "ApparatusBay1", Vector3(-1.3, 0.0, 3.65), "fire_apparatus", 4.2, 4.2)
	_marker(root, "ApparatusBay2", Vector3(4.3, 0.0, 3.65), "fire_apparatus", 4.2, 4.2)
	_marker(root, "PersonnelEntrance", Vector3(-6.75, 0.14, 4.2), "pedestrian", 1.2, 2.4)
	return root


static func _palette(k: Kit) -> void:
	# Nine finishes, one draw surface each; colors follow the neighborhood kits.
	k.material("brick", Color("8a4a3a"), 1)
	k.material("brick_dark", Color("6e3a30"), 1)
	k.material("stone", Color("dbcfb2"), 2, 0.88)
	k.material("concrete", Color("9a968c"), 2)
	k.material("roof", Color("3e3e44"), 0, 0.95)
	k.material("red", Color("b02a22"), 6, 0.6)
	k.material("frame", Color("2c332f"), 6, 0.7)
	k.material("glass", Color("1c2328"), 0, 0.5)
	k.material("metal", Color("8b9093"), 6, 0.6)


# ------------------------------------------------------------------ helpers
static func _block(k: Kit, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, finish: String) -> void:
	k.box(Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5), Vector3(absf(x1 - x0), absf(y1 - y0), absf(z1 - z0)), finish)


static func _solid(k: Kit, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float) -> void:
	k.solid_box(Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5), Vector3(absf(x1 - x0), absf(y1 - y0), absf(z1 - z0)))


## A course wrapped around a solid plan rectangle, projecting `out` on every side.
static func _course(k: Kit, x0: float, x1: float, z0: float, z1: float, y0: float, y1: float, out: float, finish: String) -> void:
	_block(k, x0 - out, x1 + out, y0, y1, z0 - out, z1 + out, finish)


## Box spanning u0..u1 along a facade, y0..y1 high and out0..out1 from its plane.
static func _slab(k: Kit, side: int, plane: float, u0: float, u1: float, y0: float, y1: float, out0: float, out1: float, finish: String) -> void:
	var u := (u0 + u1) * 0.5
	var y := (y0 + y1) * 0.5
	var o := (out0 + out1) * 0.5
	var su := absf(u1 - u0)
	var sy := absf(y1 - y0)
	var so := absf(out1 - out0)
	match side:
		FRONT:
			k.box(Vector3(u, y, plane + o), Vector3(su, sy, so), finish)
		BACK:
			k.box(Vector3(u, y, plane - o), Vector3(su, sy, so), finish)
		RIGHT:
			k.box(Vector3(plane + o, y, u), Vector3(so, sy, su), finish)
		_:
			k.box(Vector3(plane - o, y, u), Vector3(so, sy, su), finish)


## Fills a facade rectangle around openings (Rect2 in facade u/y) with as few
## boxes as possible: solid cells merge into row runs, equal runs merge upward.
## Opening sides become real reveals, so windows and doors sit in the wall.
static func _fill(k: Kit, side: int, plane: float, u0: float, u1: float, y0: float, y1: float, out0: float, out1: float, holes: Array[Rect2], finish: String) -> void:
	var us: Array[float] = [u0, u1]
	var ys: Array[float] = [y0, y1]
	for hole: Rect2 in holes:
		for value: float in [hole.position.x, hole.end.x]:
			if value > u0 and value < u1 and not us.has(value):
				us.append(value)
		for value: float in [hole.position.y, hole.end.y]:
			if value > y0 and value < y1 and not ys.has(value):
				ys.append(value)
	us.sort()
	ys.sort()
	var growing: Dictionary = {}
	for row in range(ys.size() - 1):
		var ya: float = ys[row]
		var yb: float = ys[row + 1]
		var runs: Array[Vector2] = []
		var start := -1
		for col in range(us.size() - 1):
			var center := Vector2((us[col] + us[col + 1]) * 0.5, (ya + yb) * 0.5)
			var solid := true
			for hole: Rect2 in holes:
				if hole.has_point(center):
					solid = false
					break
			if solid and start < 0:
				start = col
			elif not solid and start >= 0:
				runs.append(Vector2(us[start], us[col]))
				start = -1
		if start >= 0:
			runs.append(Vector2(us[start], us[us.size() - 1]))
		var next: Dictionary = {}
		for run: Vector2 in runs:
			next[run] = growing[run] if growing.has(run) else ya
			growing.erase(run)
		for run: Vector2 in growing:
			_slab(k, side, plane, run.x, run.y, float(growing[run]), ya, out0, out1, finish)
		growing = next
	for run: Vector2 in growing:
		_slab(k, side, plane, run.x, run.y, float(growing[run]), y1, out0, out1, finish)


## Triangle whose winding is corrected from the intended outward normal.
static func _tri(k: Kit, a: Vector3, b: Vector3, c: Vector3, finish: String, outward: Vector3) -> void:
	if (c - a).cross(b - a).dot(outward) < 0.0:
		k.triangle(a, c, b, finish)
	else:
		k.triangle(a, b, c, finish)


## Round bar between two points (tie rods, antenna arms).
static func _rod(k: Kit, p0: Vector3, p1: Vector3, radius: float, finish: String, sides: int = 6) -> void:
	var axis := p1 - p0
	var length := axis.length()
	if length < 0.001:
		return
	var dir := axis / length
	# Basis.from_euler is YXZ: pitch the cylinder's +Y off vertical, then yaw it.
	var turn := Vector3(acos(clampf(dir.y, -1.0, 1.0)), atan2(dir.x, dir.z), 0.0)
	k.cylinder((p0 + p1) * 0.5, radius, length, finish, sides, -1.0, turn)


## Double-hung window in a skin opening: dark frame 16 cm behind the face, two
## sashes and a meeting rail, optional transom light, stone sill/lintel/keystone.
static func _window(k: Kit, side: int, plane: float, u: float, y0: float, y1: float, width: float, depth: float, sill: bool, transom: float = 0.0) -> void:
	var half := width * 0.5
	_slab(k, side, plane, u - half, u + half, y0, y1, -depth, -0.16, "frame")
	var top := y1
	if transom > 0.0:
		top = y1 - transom
		_slab(k, side, plane, u - half + 0.07, u + half - 0.07, top + 0.04, y1 - 0.07, -0.17, -0.145, "glass")
		_slab(k, side, plane, u - half + 0.02, u + half - 0.02, top - 0.04, top + 0.04, -0.17, -0.12, "frame")
	var meet := y0 + (top - y0) * 0.5
	_slab(k, side, plane, u - half + 0.07, u + half - 0.07, meet + 0.035, top - 0.07, -0.17, -0.145, "glass")
	_slab(k, side, plane, u - half + 0.07, u + half - 0.07, y0 + 0.07, meet - 0.035, -0.17, -0.132, "glass")
	_slab(k, side, plane, u - half + 0.03, u + half - 0.03, meet - 0.04, meet + 0.04, -0.17, -0.115, "frame")
	if sill:
		_slab(k, side, plane, u - half - 0.09, u + half + 0.09, y0 - 0.09, y0 + 0.012, -0.17, 0.07, "stone")
	_slab(k, side, plane, u - half - 0.15, u + half + 0.15, y1, y1 + 0.27, 0.0, 0.035, "stone")
	_slab(k, side, plane, u - 0.11, u + 0.11, y1 - 0.05, y1 + 0.34, 0.0, 0.075, "stone")


## Hose-drying loft opening: dark backing and five light metal louver blades.
static func _louvers(k: Kit, side: int, plane: float, u: float, y0: float, y1: float, width: float) -> void:
	var half := width * 0.5
	_slab(k, side, plane, u - half, u + half, y0, y1, -0.2, -0.17, "frame")
	var pitch := (y1 - y0) / 6.0
	for blade in range(1, 6):
		var y := y0 + pitch * float(blade)
		_slab(k, side, plane, u - half, u + half, y - 0.035, y + 0.035, -0.16, -0.05, "metal")


## Steel service door at grade with stone lintel, drip hood and wall lamp.
static func _service_door(k: Kit, side: int, plane: float, u: float) -> void:
	_slab(k, side, plane, u - 0.5, u + 0.5, -0.02, 2.25, -0.2, -0.17, "metal")
	_slab(k, side, plane, u - 0.44, u + 0.44, 0.0, 2.19, -0.17, -0.13, "frame")
	_slab(k, side, plane, u + 0.24, u + 0.32, 0.95, 1.1, -0.13, -0.09, "metal")
	_slab(k, side, plane, u - 0.65, u + 0.65, 2.25, 2.5, 0.0, 0.04, "stone")
	_slab(k, side, plane, u - 0.72, u + 0.72, 2.6, 2.68, 0.0, 0.25, "frame")
	_slab(k, side, plane, u - 0.08, u + 0.08, 2.76, 2.92, 0.0, 0.14, "glass")


## Maltese cross: four flared, V-notched arms meeting at the center, facing +Z.
static func _maltese_cross(k: Kit, center: Vector3, radius: float) -> void:
	var tip := radius * 0.48
	var notch := radius * 0.28
	for arm in range(4):
		var angle := float(arm) * PI * 0.5
		var along := Vector3(sin(angle), cos(angle), 0.0)
		var across := Vector3(cos(angle), -sin(angle), 0.0)
		var outer := center + along * radius
		var inner := center + along * (radius - notch)
		_tri(k, center, outer - across * tip, inner, "red", Vector3.BACK)
		_tri(k, center, inner, outer + across * tip, "red", Vector3.BACK)


## Integration anchor in the same form as the other civic models.
static func _marker(root: Node3D, title: String, at: Vector3, use: String, width: float, height: float) -> void:
	var marker := Marker3D.new()
	marker.name = title
	marker.position = at
	marker.set_meta("use", use)
	marker.set_meta("clear_width_m", width)
	marker.set_meta("clear_height_m", height)
	marker.set_meta("approach_local", Vector3(0, 0, 1))
	root.add_child(marker)


# ------------------------------------------------------------------ volumes
static func _apparatus_block(k: Kit) -> void:
	# Two-storey apparatus block with quarters over the bays. A brick core sits
	# behind a 0.4 m front skin (door recesses) and 0.2 m side/rear skins.
	_block(k, -4.8, 8.5, -0.05, 8.85, -4.2, 3.6, "brick")
	_block(k, -4.6, 8.5, 8.85, 8.91, -4.2, 3.6, "roof")
	var bays: Array[Rect2] = [Rect2(-3.4, -0.05, 4.2, 4.35), Rect2(2.2, -0.05, 4.2, 4.35)]
	var front: Array[Rect2] = [Rect2(-3.4, -0.05, 4.2, 4.35), Rect2(2.2, -0.05, 4.2, 4.35), Rect2(7.1, 1.0, 0.9, 2.4)]
	for x: float in UPPER_FRONT:
		front.append(Rect2(x - 0.5, SILL_TOP, 1.0, UPPER_HEAD - SILL_TOP))
	_fill(k, FRONT, 4.0, -4.8, 8.7, -0.05, 9.3, -0.4, 0.0, front, "brick")
	var side: Array[Rect2] = []
	for z: float in SIDE_BAYS:
		side.append(Rect2(z - 0.5, 2.4, 1.0, 1.5))
		side.append(Rect2(z - 0.5, SILL_TOP, 1.0, UPPER_HEAD - SILL_TOP))
	_fill(k, RIGHT, 8.7, -4.4, 3.6, -0.05, 9.3, -0.2, 0.0, side, "brick")
	var rear: Array[Rect2] = []
	for x: float in REAR_BAYS:
		rear.append(Rect2(x - 0.5, SILL_TOP, 1.0, UPPER_HEAD - SILL_TOP))
	_fill(k, BACK, -4.4, -4.8, 8.7, 5.15, 9.3, -0.2, 0.0, rear, "brick")
	# Parapet where the block rises over the office wing roof.
	_block(k, -4.8, -4.6, 8.0, 9.3, -4.4, 0.3, "brick")
	# Gray granite base, stone belt (the lintel over both bays), sill course and
	# a corbelled dark-brick cornice wrap the street front, open side and rear.
	_fill(k, FRONT, 4.0, -4.8, 8.75, -0.05, BASE_TOP, 0.0, 0.05, bays, "concrete")
	_slab(k, RIGHT, 8.7, -4.45, 4.05, -0.05, BASE_TOP, 0.0, 0.05, "concrete")
	_course(k, -4.8, 8.7, -4.4, 4.0, BELT_BOTTOM, BELT_TOP, 0.05, "stone")
	_course(k, -4.8, 8.7, -4.4, 4.0, SILL_BOTTOM, SILL_TOP, 0.06, "stone")
	_course(k, -4.8, 8.7, -4.4, 4.0, 7.95, 8.15, 0.02, "brick_dark")
	for tier in range(3):
		var y := 8.15 + 0.15 * float(tier)
		_course(k, -4.8, 8.7, -4.4, 4.0, y, y + 0.15, 0.06 * float(tier + 1), "brick_dark")
	_block(k, -4.8, 8.76, 9.3, 9.42, 3.54, 4.06, "stone")
	_block(k, 8.44, 8.76, 9.3, 9.42, -4.46, 4.06, "stone")
	_block(k, -4.8, 8.76, 9.3, 9.42, -4.46, -4.14, "stone")
	_block(k, -4.86, -4.54, 9.3, 9.42, -4.46, 0.3, "stone")
	# Stone imposts cap the brick piers; keystones lock the belt over each bay.
	for pier: Vector2 in [Vector2(-4.8, -3.32), Vector2(0.72, 2.28), Vector2(6.32, 8.77)]:
		_slab(k, FRONT, 4.0, pier.x, pier.y, 3.95, BELT_BOTTOM, 0.0, 0.07, "stone")
	_slab(k, RIGHT, 8.7, 3.6, 4.07, 3.95, BELT_BOTTOM, 0.0, 0.07, "stone")
	for x: float in [-1.3, 4.3]:
		_slab(k, FRONT, 4.0, x - 0.28, x + 0.28, 4.18, 4.85, 0.0, 0.1, "stone")
	# ENGINE HOUSE: framed stone panel in the frieze between the bays and quarters.
	_slab(k, FRONT, 4.0, -0.9, 3.9, 4.88, 5.66, 0.0, 0.045, "stone")
	_slab(k, FRONT, 4.0, -0.98, 3.98, 4.8, 4.88, 0.0, 0.085, "stone")
	_slab(k, FRONT, 4.0, -0.98, 3.98, 5.66, 5.74, 0.0, 0.085, "stone")
	_slab(k, FRONT, 4.0, -0.98, -0.9, 4.88, 5.66, 0.0, 0.085, "stone")
	_slab(k, FRONT, 4.0, 3.9, 3.98, 4.88, 5.66, 0.0, 0.085, "stone")
	k.label("ENGINE HOUSE", Vector3(1.5, 5.27, 4.057), 88, 0.0075, INK)
	# Stepped parapet over the center pier carries the neighborhood name.
	_slab(k, FRONT, 4.0, -0.45, 3.45, 9.42, 9.78, -0.4, 0.0, "brick")
	_slab(k, FRONT, 4.0, 0.05, 2.95, 9.78, 10.1, -0.4, 0.0, "brick")
	_slab(k, FRONT, 4.0, -0.51, 0.05, 9.78, 9.9, -0.46, 0.06, "stone")
	_slab(k, FRONT, 4.0, 2.95, 3.51, 9.78, 9.9, -0.46, 0.06, "stone")
	_slab(k, FRONT, 4.0, -0.01, 3.01, 10.1, 10.22, -0.46, 0.06, "stone")
	_slab(k, FRONT, 4.0, 0.3, 2.7, 9.5, 10.0, 0.0, 0.04, "stone")
	k.label("PEN LUCY", Vector3(1.5, 9.75, 4.051), 64, 0.0072, INK)
	# Quarters windows: their sills stand 1 cm proud of the sill course and cover
	# its top in the reveal. The watch window flanks bay two.
	for x: float in UPPER_FRONT:
		_window(k, FRONT, 4.0, x, SILL_TOP, UPPER_HEAD, 1.0, 0.4, true)
	_window(k, FRONT, 4.0, 7.55, 1.0, 3.4, 0.9, 0.4, true, 0.5)
	for z: float in SIDE_BAYS:
		_window(k, RIGHT, 8.7, z, 2.4, 3.9, 1.0, 0.2, true)
		_window(k, RIGHT, 8.7, z, SILL_TOP, UPPER_HEAD, 1.0, 0.2, true)
	for x: float in REAR_BAYS:
		_window(k, BACK, -4.4, x, SILL_TOP, UPPER_HEAD, 1.0, 0.2, true)
	# Mass up to the door plane, the three piers and the wall over the doors.
	_solid(k, -4.8, 8.7, -0.05, 9.3, -4.4, 3.6)
	_solid(k, -4.8, -3.4, -0.05, BELT_BOTTOM, 3.6, 4.0)
	_solid(k, 0.8, 2.2, -0.05, BELT_BOTTOM, 3.6, 4.0)
	_solid(k, 6.4, 8.7, -0.05, BELT_BOTTOM, 3.6, 4.0)
	_solid(k, -4.8, 8.7, BELT_BOTTOM, 9.3, 3.6, 4.0)


## Six-section overhead door 0.35 m behind the pier faces: dark seams between
## sections, raised panels, a row of small dark lights, steel jambs and header.
static func _bay_door(k: Kit, x0: float, x1: float) -> void:
	var face := 3.65
	var top := BELT_BOTTOM
	_block(k, x0, x1, 0.0, top, 3.58, 3.62, "frame")
	var section := (top - 0.12) / 6.0
	var panel := (x1 - x0 - 0.04 - 0.12 * 5.0) / 4.0
	for row in range(6):
		var y := 0.02 + section * float(row)
		_block(k, x0 + 0.02, x1 - 0.02, y, y + section - 0.025, 3.6, face, "red")
		for col in range(4):
			var px := x0 + 0.14 + (panel + 0.12) * float(col)
			_block(k, px, px + panel, y + 0.11, y + section - 0.135, face, face + 0.03, "red")
			if row == 4:
				_block(k, px + 0.08, px + panel - 0.08, y + 0.17, y + section - 0.195, face + 0.03, face + 0.042, "glass")
	# Header, and the exposed steel lintel that forms the recess soffit.
	_block(k, x0, x1, top - 0.1, top, 3.6, 3.7, "frame")
	_block(k, x0, x1, top - 0.03, top, 3.6, 4.0, "frame")
	_block(k, x0, x0 + 0.08, 0.0, top, 3.6, 3.72, "frame")
	_block(k, x1 - 0.08, x1, 0.0, top, 3.6, 3.72, "frame")
	_block(k, x0 + 0.08, x1 - 0.08, 0.0, 0.05, 3.62, face + 0.025, "frame")


static func _hose_tower(k: Kit) -> void:
	# Hose tower on the corner: stair and personnel door below, drying loft
	# behind louvers, hipped cap. Its front and side stand 0.2 m proud.
	_block(k, -8.5, -4.8, -0.05, 12.4, 0.3, 4.0, "brick")
	var front: Array[Rect2] = [Rect2(-7.35, 0.14, 1.2, 2.91), Rect2(-7.225, SILL_TOP, 0.95, UPPER_HEAD - SILL_TOP), Rect2(-7.75, 9.0, 2.0, 3.0)]
	_fill(k, FRONT, 4.2, -8.7, -4.8, -0.05, 12.4, -0.2, 0.0, front, "brick")
	var side: Array[Rect2] = [Rect2(1.8, 1.0, 0.9, 2.3), Rect2(1.775, SILL_TOP, 0.95, UPPER_HEAD - SILL_TOP), Rect2(1.25, 9.0, 2.0, 3.0)]
	_fill(k, LEFT, -8.7, 0.3, 4.0, -0.05, 12.4, -0.2, 0.0, side, "brick")
	# Courses continue the apparatus datums around the shaft.
	var door: Array[Rect2] = [Rect2(-7.35, 0.14, 1.2, 1.0)]
	_fill(k, FRONT, 4.2, -8.75, -4.75, -0.05, BASE_TOP, 0.0, 0.05, door, "concrete")
	_slab(k, LEFT, -8.7, 0.25, 4.25, -0.05, BASE_TOP, 0.0, 0.05, "concrete")
	_block(k, -4.8, -4.75, -0.05, BASE_TOP, 4.0, 4.25, "concrete")
	_course(k, -8.7, -4.8, 0.3, 4.2, BELT_BOTTOM, BELT_TOP, 0.05, "stone")
	_course(k, -8.7, -4.8, 0.3, 4.2, SILL_BOTTOM, SILL_TOP, 0.06, "stone")
	_course(k, -8.7, -4.8, 0.3, 4.2, 8.47, 8.77, 0.06, "stone")
	_window(k, FRONT, 4.2, -6.75, SILL_TOP, UPPER_HEAD, 0.95, 0.2, true)
	_window(k, LEFT, -8.7, 2.25, SILL_TOP, UPPER_HEAD, 0.95, 0.2, true)
	_window(k, LEFT, -8.7, 2.25, 1.0, 3.3, 0.9, 0.2, true, 0.5)
	# Recessed upper panels: Maltese cross roundel to the street, stair slit to the side.
	_slab(k, FRONT, 4.2, -7.75, -5.75, 9.0, 12.0, -0.2, -0.17, "brick_dark")
	_slab(k, LEFT, -8.7, 1.25, 3.25, 9.0, 12.0, -0.2, -0.17, "brick_dark")
	_slab(k, FRONT, 4.2, -7.8, -5.7, 8.92, 9.02, -0.2, 0.05, "stone")
	_slab(k, LEFT, -8.7, 1.2, 3.3, 8.92, 9.02, -0.2, 0.05, "stone")
	k.cylinder(Vector3(-6.75, 10.5, 4.08), 0.62, 0.1, "stone", 16, -1.0, Vector3(PI * 0.5, 0.0, 0.0))
	_maltese_cross(k, Vector3(-6.75, 10.5, 4.138), 0.5)
	_slab(k, LEFT, -8.7, 1.95, 2.55, 9.45, 11.55, -0.17, -0.14, "frame")
	_slab(k, LEFT, -8.7, 2.02, 2.48, 9.52, 11.48, -0.14, -0.125, "glass")
	_slab(k, LEFT, -8.7, 1.9, 2.6, 9.37, 9.45, -0.17, -0.08, "stone")
	_slab(k, LEFT, -8.7, 1.9, 2.6, 11.55, 11.7, -0.17, -0.1, "stone")
	# Drying loft: inset core, louvered pairs on all four faces. The skins stop
	# at the opening heads; the solid stone impost course above is the lintel.
	_block(k, -8.5, -5.0, 12.4, 13.9, 0.5, 4.0, "brick")
	var loft_x: Array[Rect2] = [Rect2(-7.95, 12.5, 0.9, 1.25), Rect2(-6.45, 12.5, 0.9, 1.25)]
	var loft_z: Array[Rect2] = [Rect2(1.05, 12.5, 0.9, 1.25), Rect2(2.55, 12.5, 0.9, 1.25)]
	_fill(k, FRONT, 4.2, -8.7, -4.8, 12.4, 13.75, -0.2, 0.0, loft_x, "brick")
	_fill(k, BACK, 0.3, -8.7, -4.8, 12.4, 13.75, -0.2, 0.0, loft_x, "brick")
	_fill(k, LEFT, -8.7, 0.5, 4.0, 12.4, 13.75, -0.2, 0.0, loft_z, "brick")
	_fill(k, RIGHT, -4.8, 0.5, 4.0, 12.4, 13.75, -0.2, 0.0, loft_z, "brick")
	for x: float in [-7.5, -6.0]:
		_louvers(k, FRONT, 4.2, x, 12.5, 13.75, 0.9)
		_louvers(k, BACK, 0.3, x, 12.5, 13.75, 0.9)
	for z: float in [1.5, 3.0]:
		_louvers(k, LEFT, -8.7, z, 12.5, 13.75, 0.9)
		_louvers(k, RIGHT, -4.8, z, 12.5, 13.75, 0.9)
	_course(k, -8.7, -4.8, 0.3, 4.2, 12.25, 12.45, 0.06, "stone")
	_course(k, -8.7, -4.8, 0.3, 4.2, 13.75, 13.9, 0.05, "stone")
	# Corbelled cornice, eave board and a hipped cap with a finial and rod.
	_course(k, -8.7, -4.8, 0.3, 4.2, 13.9, 14.05, 0.07, "brick_dark")
	_course(k, -8.7, -4.8, 0.3, 4.2, 14.05, 14.2, 0.14, "brick_dark")
	_course(k, -8.7, -4.8, 0.3, 4.2, 14.2, 14.36, 0.22, "stone")
	_course(k, -8.7, -4.8, 0.3, 4.2, 14.36, 14.44, 0.25, "roof")
	var apex := Vector3(-6.75, 16.25, 2.25)
	var corners: Array[Vector3] = [Vector3(-8.95, 14.44, 4.45), Vector3(-4.55, 14.44, 4.45), Vector3(-4.55, 14.44, 0.05), Vector3(-8.95, 14.44, 0.05)]
	for i in range(4):
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		var mid := (a + b) * 0.5
		var outward := Vector3(mid.x - apex.x, 0.0, mid.z - apex.z).normalized() + Vector3.UP
		_tri(k, a, b, apex, "roof", outward)
	k.cylinder(Vector3(-6.75, 16.45, 2.25), 0.07, 0.5, "metal", 6)
	k.cylinder(Vector3(-6.75, 16.76, 2.25), 0.13, 0.16, "metal", 8)
	k.cylinder(Vector3(-6.75, 17.15, 2.25), 0.018, 0.62, "metal", 4)
	_solid(k, -8.7, -4.8, -0.05, 14.4, 0.3, 4.2)


static func _personnel_entry(k: Kit) -> void:
	# Accessible personnel door in the tower: landing 0.14 m up with a 1:12
	# ramp to the walk, stone surround, transom, lanterns and a tie-rod canopy.
	var x := -6.75
	var face := 4.2
	_slab(k, FRONT, face, x - 0.6, x + 0.6, 0.14, 3.05, -0.2, -0.17, "frame")
	_slab(k, FRONT, face, x - 0.5, x + 0.5, 0.14, 2.55, -0.17, -0.12, "red")
	_slab(k, FRONT, face, x - 0.19, x + 0.19, 1.45, 2.3, -0.12, -0.105, "glass")
	_slab(k, FRONT, face, x + 0.28, x + 0.36, 0.95, 1.25, -0.12, -0.075, "metal")
	_slab(k, FRONT, face, x - 0.6, x + 0.6, 2.55, 2.63, -0.17, -0.11, "frame")
	_slab(k, FRONT, face, x - 0.52, x + 0.52, 2.63, 2.99, -0.17, -0.145, "glass")
	_slab(k, FRONT, face, x - 0.6, x + 0.6, 0.12, 0.155, -0.17, 0.01, "stone")
	_slab(k, FRONT, face, x - 0.85, x - 0.6, 0.14, 3.05, 0.0, 0.08, "stone")
	_slab(k, FRONT, face, x + 0.6, x + 0.85, 0.14, 3.05, 0.0, 0.08, "stone")
	_slab(k, FRONT, face, x - 1.0, x + 1.0, 3.05, 3.5, 0.0, 0.12, "stone")
	_slab(k, FRONT, face, x - 1.08, x + 1.08, 3.5, 3.58, 0.0, 0.18, "stone")
	k.label("FIRE DEPT", Vector3(x, 3.275, face + 0.131), 52, 0.0055, INK)
	_block(k, x - 1.3, x + 1.3, 3.72, 3.84, face, face + 1.2, "frame")
	_block(k, x - 1.32, x + 1.32, 3.64, 3.88, face + 1.16, face + 1.24, "frame")
	for rod_x: float in [x - 1.15, x + 1.15]:
		_rod(k, Vector3(rod_x, 3.86, face + 1.1), Vector3(rod_x, 4.62, face + 0.02), 0.022, "frame", 5)
		_block(k, rod_x - 0.07, rod_x + 0.07, 4.55, 4.69, face, face + 0.07, "frame")
	for lamp_x: float in [x - 1.45, x + 1.45]:
		_block(k, lamp_x - 0.03, lamp_x + 0.03, 2.4, 2.46, face, face + 0.3, "frame")
		_block(k, lamp_x - 0.1, lamp_x + 0.1, 2.0, 2.34, face + 0.2, face + 0.4, "glass")
		_block(k, lamp_x - 0.13, lamp_x + 0.13, 2.34, 2.4, face + 0.17, face + 0.43, "frame")
		_block(k, lamp_x - 0.06, lamp_x + 0.06, 1.94, 2.0, face + 0.24, face + 0.36, "frame")
	# Landing and ramp share one convex collider; the ramp toe meets the walk.
	_block(k, -8.35, -5.15, -0.05, 0.14, face, 5.6, "concrete")
	var hull := PackedVector3Array()
	for side_x: float in [-8.35, -5.15]:
		var outward := Vector3.LEFT if side_x < x else Vector3.RIGHT
		_tri(k, Vector3(side_x, 0.012, 5.6), Vector3(side_x, 0.14, 5.6), Vector3(side_x, 0.012, 7.2), "concrete", outward)
		for point: Vector3 in [Vector3(side_x, -0.05, face), Vector3(side_x, 0.14, face), Vector3(side_x, 0.14, 5.6), Vector3(side_x, 0.012, 7.2), Vector3(side_x, -0.05, 7.2)]:
			hull.append(point)
	_tri(k, Vector3(-8.35, 0.14, 5.6), Vector3(-5.15, 0.14, 5.6), Vector3(-5.15, 0.012, 7.2), "concrete", Vector3.UP)
	_tri(k, Vector3(-8.35, 0.14, 5.6), Vector3(-5.15, 0.012, 7.2), Vector3(-8.35, 0.012, 7.2), "concrete", Vector3.UP)
	k.solid_convex(hull)


static func _office_wing(k: Kit) -> void:
	# Two-storey office and quarters behind the tower, facing the side street.
	_block(k, -8.3, -4.8, -0.05, 8.3, -8.0, 0.3, "brick")
	_block(k, -8.3, -4.8, 8.3, 8.36, -8.0, 0.3, "roof")
	var side: Array[Rect2] = []
	for z: float in OFFICE_BAYS:
		side.append(Rect2(z - 0.525, 0.95, 1.05, 2.6))
		side.append(Rect2(z - 0.525, SILL_TOP, 1.05, UPPER_HEAD - SILL_TOP))
	_fill(k, LEFT, -8.5, -8.0, 0.3, -0.05, 8.7, -0.2, 0.0, side, "brick")
	var rear: Array[Rect2] = [Rect2(-7.175, 0.95, 1.05, 2.6), Rect2(-7.175, SILL_TOP, 1.05, UPPER_HEAD - SILL_TOP)]
	_fill(k, BACK, -8.2, -8.5, -4.8, -0.05, 8.7, -0.2, 0.0, rear, "brick")
	# Parapet over the low annex roof; the wing sits 0.6 m below the main block.
	_block(k, -5.0, -4.8, 8.0, 8.7, -8.2, -4.4, "brick")
	_course(k, -8.5, -4.8, -8.2, 0.3, -0.05, BASE_TOP, 0.05, "concrete")
	_course(k, -8.5, -4.8, -8.2, 0.3, BELT_BOTTOM, BELT_TOP, 0.05, "stone")
	_course(k, -8.5, -4.8, -8.2, 0.3, SILL_BOTTOM, SILL_TOP, 0.06, "stone")
	_course(k, -8.5, -4.8, -8.2, 0.3, 7.95, 8.1, 0.06, "brick_dark")
	_course(k, -8.5, -4.8, -8.2, 0.3, 8.1, 8.25, 0.12, "brick_dark")
	_block(k, -8.56, -8.24, 8.7, 8.82, -8.26, 0.3, "stone")
	_block(k, -8.56, -4.8, 8.7, 8.82, -8.26, -7.94, "stone")
	_block(k, -5.06, -4.74, 8.7, 8.82, -8.26, -4.4, "stone")
	for z: float in OFFICE_BAYS:
		_window(k, LEFT, -8.5, z, 0.95, 3.55, 1.05, 0.2, true, 0.6)
		_window(k, LEFT, -8.5, z, SILL_TOP, UPPER_HEAD, 1.05, 0.2, true)
	_window(k, BACK, -8.2, -6.65, 0.95, 3.55, 1.05, 0.2, true, 0.6)
	_window(k, BACK, -8.2, -6.65, SILL_TOP, UPPER_HEAD, 1.05, 0.2, true)
	_solid(k, -8.5, -4.8, -0.05, 8.7, -8.2, 0.3)


static func _rear_annex(k: Kit) -> void:
	# One-storey rear apparatus annex: low roof, service doors, high windows.
	_block(k, -4.8, 8.3, -0.05, 5.15, -8.0, -4.2, "brick")
	_block(k, -4.8, 8.3, 5.15, 5.21, -8.0, -4.4, "roof")
	var side: Array[Rect2] = [Rect2(-6.75, -0.05, 1.0, 2.3)]
	_fill(k, RIGHT, 8.5, -8.0, -4.4, -0.05, 5.55, -0.2, 0.0, side, "brick")
	var rear: Array[Rect2] = [Rect2(6.7, -0.05, 1.0, 2.3)]
	for x: float in ANNEX_BAYS:
		rear.append(Rect2(x - 0.6, 2.6, 1.2, 1.3))
	_fill(k, BACK, -8.2, -4.8, 8.5, -0.05, 5.55, -0.2, 0.0, rear, "brick")
	var side_base: Array[Rect2] = [Rect2(-6.75, -0.05, 1.0, 0.7)]
	_fill(k, RIGHT, 8.5, -8.25, -4.4, -0.05, BASE_TOP, 0.0, 0.05, side_base, "concrete")
	var rear_base: Array[Rect2] = [Rect2(6.7, -0.05, 1.0, 0.7)]
	_fill(k, BACK, -8.2, -4.8, 8.55, -0.05, BASE_TOP, 0.0, 0.05, rear_base, "concrete")
	_course(k, -4.8, 8.5, -8.2, -4.4, 4.75, 4.9, 0.05, "brick_dark")
	_course(k, -4.8, 8.5, -8.2, -4.4, 4.9, 5.05, 0.1, "brick_dark")
	_block(k, 8.24, 8.56, 5.55, 5.67, -8.26, -4.4, "stone")
	_block(k, -4.8, 8.56, 5.55, 5.67, -8.26, -7.94, "stone")
	for x: float in ANNEX_BAYS:
		_window(k, BACK, -8.2, x, 2.6, 3.9, 1.2, 0.2, true)
	_service_door(k, RIGHT, 8.5, -6.25)
	_service_door(k, BACK, -8.2, 7.2)
	_solid(k, -4.8, 8.5, -0.05, 5.55, -8.2, -4.4)


static func _forecourt(k: Kit) -> void:
	# Apparatus apron, entry walk and narrow side/rear walks: flush visual
	# paving only. No colliders; the root foundation is the walkable floor.
	_block(k, -4.8, 9.0, -0.08, 0.012, 3.6, 8.5, "concrete")
	_block(k, -9.0, -4.8, -0.08, 0.012, 4.2, 8.5, "concrete")
	_block(k, -9.0, -8.5, -0.08, 0.012, -8.5, 4.2, "concrete")
	_block(k, 8.5, 9.0, -0.08, 0.012, -8.5, 3.6, "concrete")
	_block(k, -8.5, 8.5, -0.08, 0.012, -8.5, -8.2, "concrete")
	# Trench drain across the apron just outside the doors.
	_block(k, -3.3, 6.3, 0.012, 0.02, 4.32, 4.48, "frame")


static func _roof_equipment(k: Kit) -> void:
	var deck := 8.91
	# Siren on a pipe mast near the front: reads over the parapet from the street.
	_block(k, 6.15, 6.65, deck, deck + 0.08, 1.15, 1.65, "metal")
	k.cylinder(Vector3(6.4, deck + 1.5, 1.4), 0.055, 3.0, "metal", 6)
	k.cylinder(Vector3(6.4, deck + 3.17, 1.4), 0.24, 0.34, "red", 10)
	k.cylinder(Vector3(6.4, deck + 3.365, 1.4), 0.27, 0.05, "metal", 10)
	for dir: float in [-1.0, 1.0]:
		k.cylinder(Vector3(6.4 + dir * 0.4, deck + 3.17, 1.4), 0.08, 0.32, "metal", 8, 0.19, Vector3(PI * 0.5, dir * PI * 0.5, 0.0))
	# Radio mast with two short arms at the rear corner of the main roof.
	k.cylinder(Vector3(7.9, deck + 0.06, -3.5), 0.22, 0.12, "concrete", 8)
	k.cylinder(Vector3(7.9, deck + 2.25, -3.5), 0.045, 4.5, "metal", 6)
	_rod(k, Vector3(7.45, deck + 3.6, -3.5), Vector3(8.35, deck + 3.6, -3.5), 0.02, "metal", 4)
	_rod(k, Vector3(7.9, deck + 4.15, -3.9), Vector3(7.9, deck + 4.15, -3.1), 0.02, "metal", 4)
	# Packaged rooftop unit on a curb, fans up and its grille toward the street.
	_block(k, 3.5, 6.0, deck, deck + 0.16, -3.4, -1.2, "concrete")
	_block(k, 3.6, 5.9, deck + 0.16, deck + 1.56, -3.3, -1.3, "metal")
	_block(k, 3.7, 5.8, deck + 0.35, deck + 1.25, -1.3, -1.27, "frame")
	for x: float in [4.15, 5.35]:
		k.cylinder(Vector3(x, deck + 1.62, -2.3), 0.45, 0.12, "frame", 10)
	# Two mushroom exhaust fans over the apparatus floor and a roof hatch.
	for x: float in [0.4, 1.9]:
		k.cylinder(Vector3(x, deck + 0.25, -2.6), 0.24, 0.5, "metal", 8)
		k.cylinder(Vector3(x, deck + 0.6, -2.6), 0.4, 0.2, "metal", 8, 0.12)
	_block(k, -3.5, -2.6, deck, deck + 0.42, -1.4, -0.5, "metal")
	_block(k, -3.55, -2.55, deck + 0.42, deck + 0.47, -1.45, -0.45, "metal")
	# Condensing unit and two apparatus exhaust stacks on the annex roof.
	var low := 5.21
	_block(k, 1.2, 2.8, low, low + 0.12, -7.2, -5.8, "concrete")
	_block(k, 1.3, 2.7, low + 0.12, low + 1.02, -7.1, -5.9, "metal")
	k.cylinder(Vector3(2.0, low + 1.08, -6.5), 0.4, 0.12, "frame", 10)
	for x: float in [5.4, 6.4]:
		k.cylinder(Vector3(x, low + 0.9, -6.4), 0.14, 1.8, "metal", 8)
		k.cylinder(Vector3(x, low + 1.9, -6.4), 0.26, 0.2, "metal", 8, 0.04)
	# Office wing: skylight over the stair landing and a plumbing vent.
	var office := 8.36
	_block(k, -7.3, -6.0, office, office + 0.3, -5.4, -3.8, "frame")
	_block(k, -7.2, -6.1, office + 0.3, office + 0.38, -5.3, -3.9, "glass")
	k.cylinder(Vector3(-5.6, office + 0.45, -6.8), 0.08, 0.9, "metal", 6)
	# Rear downspouts with leader heads on the annex and the office wing.
	for x: float in [-4.45, 8.15]:
		_block(k, x - 0.06, x + 0.06, 0.05, 5.3, -8.34, -8.22, "metal")
		_block(k, x - 0.16, x + 0.16, 5.15, 5.45, -8.42, -8.2, "metal")
	_block(k, -8.21, -8.09, 0.05, 8.5, -8.34, -8.22, "metal")
	_block(k, -8.31, -7.99, 8.3, 8.6, -8.42, -8.2, "metal")
