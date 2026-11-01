extends RefCounted
## Procedural low-poly shells for the catalog vehicles (city_car_catalog.gd).
## Returns material-free SurfaceTool groups keyed by the shared CityCarModels
## material ids (paint, trim, glass, metal, headlamp, tail); CityCarModels
## assigns its shared materials, indexes, adds LODs and caches the meshes.
## Every vertex carries a colour. Paint uses it as a linear multiplier on the
## instance/traffic paint (two-tone, cladding, blackout pillars, road dust);
## the fixed-colour materials ignore it. Faces wind clockwise seen from outside
## (Godot front faces) and store outward normals, so double-sided materials
## still light correctly. Body panels are flat shaded; tyres are smooth.

const Catalog := preload("res://scripts/city/city_car_catalog.gd")
const NEAR_SEGMENTS := 12
const FAR_SEGMENTS := 7
const WHITE := Color(1, 1, 1)

static func _st(groups: Dictionary, id: String) -> SurfaceTool:
	if not groups.has(id):
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		groups[id] = builder
	return groups[id]

static func _shade(value: float) -> Color:
	return Color(value, value, value)

## Planar-ish polygon (Vector3 items) listed around its edge in either
## direction; `outward` selects the visible side. Ear clipping also handles
## concave glass outlines without overlapping or reversed fan triangles.
static func _poly(groups: Dictionary, id: String, points: Array, color: Color, outward: Vector3) -> void:
	var count := points.size()
	if count < 3:
		return
	var normal := Vector3.ZERO
	for i in count:
		var a: Vector3 = points[i]
		var b: Vector3 = points[(i + 1) % count]
		normal += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
	if normal.length_squared() < 0.00000001:
		return
	normal = normal.normalized()
	if normal.dot(outward) < 0.0:
		normal = -normal
	# Project onto the polygon plane and triangulate the outline rather than
	# fanning from a corner; shaped windows can have concave sill/roof edges.
	var tangent := normal.cross(Vector3.UP if absf(normal.y) < .9 else Vector3.RIGHT).normalized()
	var bitangent := normal.cross(tangent).normalized()
	var projected := PackedVector2Array()
	for point in points:
		var p: Vector3 = point
		projected.append(Vector2(p.dot(tangent),p.dot(bitangent)))
	var triangles := Geometry2D.triangulate_polygon(projected)
	var builder := _st(groups, id)
	for i in range(0,triangles.size(),3):
		var a: Vector3 = points[triangles[i]]
		var b: Vector3 = points[triangles[i+1]]
		var c: Vector3 = points[triangles[i+2]]
		var cross := (b-a).cross(c-a)
		if cross.length_squared() < 0.000000001:
			continue
		var order: Array = [a,c,b] if cross.dot(normal)>0.0 else [a,b,c]
		for p in order:
			builder.set_color(color)
			builder.set_normal(normal)
			builder.add_vertex(p)

## Smooth-shaded quad for round parts (tyres): per-vertex normals.
static func _smooth_quad(groups: Dictionary, id: String, pose: Transform3D, points: Array, normals: Array) -> void:
	var world: Array[Vector3] = []
	var turned: Array[Vector3] = []
	for i in 4:
		var point: Vector3 = points[i]
		var normal: Vector3 = normals[i]
		world.append(pose * point)
		turned.append((pose.basis * normal).normalized())
	var average := (turned[0] + turned[1] + turned[2] + turned[3]).normalized()
	var builder := _st(groups, id)
	for tri in [[0, 1, 2], [0, 2, 3]]:
		var a: int = tri[0]
		var b: int = tri[1]
		var c: int = tri[2]
		var cross := (world[b] - world[a]).cross(world[c] - world[a])
		if cross.length_squared() < 0.000000001:
			continue
		var order: Array = [a, c, b] if cross.dot(average) > 0.0 else [a, b, c]
		for index in order:
			builder.set_color(WHITE)
			builder.set_normal(turned[int(index)])
			builder.add_vertex(world[int(index)])

static func _box(groups: Dictionary, id: String, center: Vector3, size: Vector3, color := WHITE, basis := Basis.IDENTITY) -> void:
	var axes: Array[Vector3] = [basis.x.normalized() * size.x * 0.5, basis.y.normalized() * size.y * 0.5, basis.z.normalized() * size.z * 0.5]
	for axis in 3:
		var u := axes[(axis + 1) % 3]
		var v := axes[(axis + 2) % 3]
		for direction in [-1.0, 1.0]:
			var face: Vector3 = center + axes[axis] * float(direction)
			_poly(groups, id, [face - u - v, face + u - v, face + u + v, face - u + v], color, axes[axis] * float(direction))

## Thin oriented bar from a to b (x thickness, z depth), for sloped shut lines.
static func _bar(groups: Dictionary, id: String, a: Vector3, b: Vector3, thickness: float, depth: float, color := WHITE) -> void:
	var up := (b - a).normalized()
	var right := (Vector3.RIGHT - up * up.dot(Vector3.RIGHT)).normalized()
	var forward := right.cross(up).normalized()
	_box(groups, id, (a + b) * 0.5, Vector3(thickness, a.distance_to(b), depth), color, Basis(right, up, forward))

## A gasket is a flat ribbon around the pane, not a second raised glass box.
## Reuses trim and adds only two triangles per edge, including shaped panes.
static func _gasket(groups: Dictionary, outline: Array, outward: Vector3, width := 0.016) -> void:
	var center := Vector3.ZERO
	for point in outline:
		center += Vector3(point)
	center /= float(outline.size())
	for i in outline.size():
		var a: Vector3 = outline[i]
		var b: Vector3 = outline[(i + 1) % outline.size()]
		var inner_a := a + a.direction_to(center) * width
		var inner_b := b + b.direction_to(center) * width
		var offset := outward.normalized() * 0.001
		_poly(groups, "trim", [a + offset, b + offset, inner_b + offset, inner_a + offset], WHITE, outward)

## Eight-corner fascia skin; chamfered corners read as a stamped lamp bezel.
static func _fascia_skin(groups: Dictionary, id: String, center: Vector3, width: float, height: float, outward: float) -> void:
	var x := width * 0.5
	var y := height * 0.5
	# Narrow vertical truck lenses (and thin reflector dividers) need the
	# bevel bounded by BOTH dimensions or the polygon self-intersects.
	var cut := minf(minf(width, height) * 0.22, 0.035)
	var outline: Array[Vector3] = []
	for p in [Vector2(-x + cut, -y), Vector2(x - cut, -y), Vector2(x, -y + cut), Vector2(x, y - cut),
		Vector2(x - cut, y), Vector2(-x + cut, y), Vector2(-x, y - cut), Vector2(-x, -y + cut)]:
		outline.append(center + Vector3(p.x, p.y, 0))
	_poly(groups, id, outline, WHITE, Vector3(0, 0, outward))

## Closed loft through rings with identical point counts. band_colors[k] tints
## the band from ring point k to k+1 (wrapping). Caps are optional. Facing is
## judged from the section centre; axial_bias tips near-vertical end faces
## (van back, pickup cab back) unambiguously toward -Z/+Z.
static func _loft(groups: Dictionary, id: String, rings: Array, band_colors: Array[Color], cap_rear: Color, cap_front: Color, caps := true, axial_bias := 0.0) -> void:
	var centers: Array[Vector3] = []
	for ring in rings:
		var sum := Vector3.ZERO
		for p in ring:
			sum += p
		centers.append(sum / float(ring.size()))
	for i in range(1, rings.size()):
		var previous: Array = rings[i - 1]
		var current: Array = rings[i]
		var axis := (centers[i - 1] + centers[i]) * 0.5
		for k in previous.size():
			var next := (k + 1) % previous.size()
			var quad: Array[Vector3] = [previous[k], current[k], current[next], previous[next]]
			var middle := (quad[0] + quad[1] + quad[2] + quad[3]) * 0.25
			var hint := middle - axis
			hint.z = axial_bias
			_poly(groups, id, quad, band_colors[k], hint)
	if not caps:
		return
	_poly(groups, id, rings[0], cap_rear, Vector3(0, 0, -1))
	_poly(groups, id, rings[rings.size() - 1], cap_front, Vector3(0, 0, 1))

# --- Body -------------------------------------------------------------------

static func _stations(kind: String, from_z: float, to_z: float) -> Array[float]:
	var c := Catalog.config(kind)
	var front := Catalog.body_front(kind)
	var rear := Catalog.body_rear(kind)
	var raw: Array[float] = [from_z, to_z]
	for d in [0.06, 0.16, 0.32]:
		raw.append(front - float(d))
		raw.append(rear + float(d))
	raw.append_array(Catalog.arch_stations(kind))
	for point in c.deck:
		raw.append(float(point[0]))
	for station in c.greenhouse:
		raw.append(float(station[0]))
	raw.sort()
	var result: Array[float] = []
	for z in raw:
		if z < from_z - 0.0001 or z > to_z + 0.0001:
			continue
		if not result.is_empty() and z - result[result.size() - 1] < 0.025:
			if is_equal_approx(z, to_z):
				result[result.size() - 1] = to_z
			continue
		result.append(z)
	return result

static func _profile_heights(low: float, accent: float, top: float) -> Array[float]:
	var ys: Array[float] = [low, low + 0.05, accent, top - 0.16, top - 0.06, top]
	for i in range(1, ys.size()):
		ys[i] = maxf(ys[i], ys[i - 1] + 0.008)
	ys[5] = top
	for i in range(4, 0, -1):
		ys[i] = minf(ys[i], ys[i + 1] - 0.008)
	return ys

## Twelve-point section: rocker, lower (accent), two side bands, shoulder and
## a rolled deck edge, mirrored. Points run up -X, across the deck, down +X.
static func _lower_ring(kind: String, z: float) -> Array[Vector3]:
	var c := Catalog.config(kind)
	var hw := Catalog.half_width(kind, z)
	var ys := _profile_heights(Catalog.bottom(kind, z), float(c.accent_y), Catalog.upper(kind, z))
	var round_edge: float = c.deck_round
	var xs: Array[float] = [0.90, 0.975, 1.0, 1.0, lerpf(1.0, round_edge, 0.4), round_edge]
	var ring: Array[Vector3] = []
	for i in 6:
		ring.append(Vector3(-xs[i] * hw, ys[i], z))
	for i in range(5, -1, -1):
		ring.append(Vector3(xs[i] * hw, ys[i], z))
	return ring

static func _lower_colors(kind: String) -> Array[Color]:
	var s: Dictionary = Catalog.config(kind).shades
	var rocker := _shade(float(s.rocker))
	var lower := _shade(float(s.lower))
	var colors: Array[Color] = [rocker, lower, WHITE, WHITE, WHITE, WHITE, WHITE, WHITE, WHITE, lower, rocker, _shade(float(s.under))]
	return colors

static func _lower_body(groups: Dictionary, kind: String, from_z: float, to_z: float) -> void:
	var rings: Array = []
	for z in _stations(kind, from_z, to_z):
		rings.append(_lower_ring(kind, z))
	_loft(groups, "paint", rings, _lower_colors(kind), WHITE, WHITE)

static func _greenhouse(groups: Dictionary, kind: String) -> void:
	var c := Catalog.config(kind)
	var s: Dictionary = c.shades
	var pillar := _shade(float(s.pillar))
	var roof := _shade(float(s.roof))
	var count: int = c.greenhouse.size()
	var rings: Array = []
	for index in count:
		var st := Catalog.greenhouse_station(kind, index)
		var bh: float = st.base_half
		var th: float = st.top_half
		var base: float = st.base
		var top: float = st.top
		var z: float = st.z
		rings.append([Vector3(-bh, base - 0.02, z), Vector3(-th, top - 0.035, z), Vector3(-th * 0.95, top, z),
			Vector3(th * 0.95, top, z), Vector3(th, top - 0.035, z), Vector3(bh, base - 0.02, z)])
	var under := _shade(float(s.under))
	# Sloped windscreen/backlight faces take the pillar shade; only the true
	# roof (between two roof stations) takes the roof shade (landau, etc.).
	for i in range(1, count):
		var is_roof := i > 1 and i < count - 1
		var top_color := roof if is_roof else pillar
		var colors: Array[Color] = [pillar, top_color, top_color, top_color, pillar, under]
		var bias := -0.4 if i == 1 else (0.4 if i == count - 1 else 0.0)
		_loft(groups, "paint", [rings[i - 1], rings[i]], colors, pillar, pillar, false, bias)
	_poly(groups, "paint", rings[0], pillar, Vector3(0, 0, -1))
	_poly(groups, "paint", rings[count - 1], pillar, Vector3(0, 0, 1))

## Side glass for one span: follows the sill and the roof/pillar lines and is
## clipped wherever the greenhouse side becomes too short (A/C-pillar slopes).
static func _side_window(groups: Dictionary, kind: String, z0: float, z1: float) -> void:
	var c := Catalog.config(kind)
	var stations: Array = c.greenhouse
	var first: Array = stations[0]
	var last: Array = stations[stations.size() - 1]
	z0 = maxf(z0, float(first[0]))
	z1 = minf(z1, float(last[0]))
	if z1 - z0 < 0.05:
		return
	var samples: Array[float] = [z0, z1]
	for station in stations:
		var z: float = station[0]
		if z > z0 + 0.01 and z < z1 - 0.01:
			samples.append(z)
	samples.sort()
	var spans: Array[float] = []
	for i in samples.size():
		var z := samples[i]
		var room := _window_room(kind, z)
		if i > 0:
			var previous := samples[i - 1]
			var before := _window_room(kind, previous)
			if (before >= 0.0) != (room >= 0.0):
				spans.append(lerpf(previous, z, before / (before - room)))
		if room >= 0.0:
			spans.append(z)
	if spans.size() < 2:
		return
	for side in [-1.0, 1.0]:
		var outline: Array[Vector3] = []
		for z in spans:
			var g := Catalog.greenhouse_at(kind, z)
			outline.append(_glass_point(g, float(g.base) + 0.06, side))
		for i in range(spans.size() - 1, -1, -1):
			var g := Catalog.greenhouse_at(kind, spans[i])
			outline.append(_glass_point(g, float(g.top) - 0.08, side))
		_poly(groups, "glass", outline, WHITE, Vector3(side, 0, 0))
		_gasket(groups, outline, Vector3(side, 0, 0))

static func _window_room(kind: String, z: float) -> float:
	var g := Catalog.greenhouse_at(kind, z)
	return (float(g.top) - 0.08) - (float(g.base) + 0.06) - 0.05

static func _glass_point(g: Dictionary, y: float, side: float) -> Vector3:
	var y0: float = float(g.base) - 0.02
	var y1: float = float(g.top) - 0.035
	var t := clampf((y - y0) / maxf(y1 - y0, 0.001), 0.0, 1.0)
	return Vector3(side * (lerpf(float(g.base_half), float(g.top_half), t) + 0.010), y, float(g.z))

## Windscreen (front) or backlight (rear) on the sloped greenhouse face.
static func _end_glass(groups: Dictionary, kind: String, front: bool, t0: float, t1: float, inset: float, split: bool) -> void:
	var count: int = Catalog.config(kind).greenhouse.size()
	var base := Catalog.greenhouse_station(kind, count - 1 if front else 0)
	var roof := Catalog.greenhouse_station(kind, count - 2 if front else 1)
	var corners: Array[Vector3] = []
	for t in [t0, t1]:
		for side in [-1.0, 1.0]:
			var b := Vector3(side * float(base.top_half) * 0.95, float(base.top), float(base.z))
			var r := Vector3(side * float(roof.top_half) * 0.95, float(roof.top), float(roof.z))
			var p := b.lerp(r, t)
			p.x -= side * inset
			corners.append(p)
	# corners: low-left, low-right, high-left, high-right
	var outward := Vector3(0, 0.35, 1.0 if front else -1.0)
	var panes: Array = []
	if split:
		for pane in [[0.0, 0.47], [0.53, 1.0]]:
			var u0: float = pane[0]
			var u1: float = pane[1]
			panes.append([corners[0].lerp(corners[1], u0), corners[0].lerp(corners[1], u1),
				corners[2].lerp(corners[3], u1), corners[2].lerp(corners[3], u0)])
	else:
		panes.append([corners[0], corners[1], corners[3], corners[2]])
	for pane in panes:
		var quad: Array[Vector3] = []
		quad.assign(pane)
		var normal := (quad[1] - quad[0]).cross(quad[3] - quad[0]).normalized()
		if normal.dot(outward) < 0.0:
			normal = -normal
		for i in 4:
			quad[i] += normal * 0.012
		_poly(groups, "glass", quad, WHITE, normal)
		_gasket(groups, quad, normal, 0.018)

static func _fascia(groups: Dictionary, kind: String, front: bool) -> void:
	var c := Catalog.config(kind)
	var spec: Dictionary = c.front if front else c.rear
	var s: Dictionary = c.shades
	var outward := 1.0 if front else -1.0
	var z := Catalog.body_front(kind) if front else Catalog.body_rear(kind)
	var hw := Catalog.half_width(kind, z)
	var proud: float = Catalog.BUMPER_PROUD
	# Bumper face sits 4mm inside the overall extent; plates/intakes reach it.
	var bumper: Array = spec.bumper
	var y0: float = bumper[0]
	var y1: float = bumper[1]
	var material := str(bumper[2])
	var bumper_depth := 0.13
	var bumper_z := z + outward * (proud - 0.004 - bumper_depth * 0.5)
	var bumper_half := Catalog.half_width(kind, z - outward * 0.06) * 0.985
	var bumper_color := _shade(float(s.bumper)) if material == "paint" else WHITE
	var bumper_rings: Array = []
	for depth in [-bumper_depth * 0.5, bumper_depth * 0.5]:
		var corner := 0.045
		var ring: Array[Vector3] = []
		for point in [Vector2(-bumper_half + corner, y0), Vector2(bumper_half - corner, y0), Vector2(bumper_half, y0 + corner),
			Vector2(bumper_half, y1 - corner), Vector2(bumper_half - corner, y1), Vector2(-bumper_half + corner, y1),
			Vector2(-bumper_half, y1 - corner), Vector2(-bumper_half, y0 + corner)]:
			ring.append(Vector3(point.x, point.y, bumper_z + float(depth)))
		bumper_rings.append(ring)
	var bumper_colors: Array[Color] = []
	for i in 8:
		bumper_colors.append(bumper_color)
	_loft(groups, material, bumper_rings, bumper_colors, bumper_color, bumper_color)
	var lamp: Array = spec.lamp
	var lamp_w: float = lamp[0]
	var lamp_h: float = lamp[1]
	var lamp_y: float = lamp[2]
	var lamp_x := minf(float(lamp[3]) * hw, hw - lamp_w * 0.5 - 0.005)
	for side in [-1.0, 1.0]:
		var center := Vector3(float(side) * lamp_x, lamp_y, z + outward * 0.009)
		_fascia_skin(groups, "trim", center, lamp_w + 0.028, lamp_h + 0.026, outward)
		_fascia_skin(groups, "headlamp" if front else "tail", center + Vector3(0, 0, outward * 0.002), lamp_w, lamp_h, outward)
		# One reflector divider makes the broad lenses read as assemblies.
		var split := center + Vector3(side * lamp_w * 0.18, 0, outward * 0.003)
		_fascia_skin(groups, "metal" if front else "headlamp", split, 0.018 if front else lamp_w * 0.18, lamp_h * 0.72, outward)
	if front:
		var grille: Array = spec.grille
		var gw: float = grille[0]
		var gh: float = grille[1]
		var gy: float = grille[2]
		_box(groups, str(grille[3]), Vector3(0, gy, z + 0.0), Vector3(gw, gh, 0.012))
		# Fine horizontal grille rails stay inside the original body envelope.
		if gh >= 0.07:
			for gy_offset in [-0.22, 0.22]:
				_fascia_skin(groups, "metal" if str(grille[3]) == "trim" else "trim",
					Vector3(0, gy + gh * float(gy_offset), z + 0.008), gw * 0.86, 0.009, 1.0)
		var extras: Array = c.extras
		if extras.has("grille_bars"):
			for i in 3:
				var y := gy - gh * 0.30 + gh * 0.30 * float(i)
				_box(groups, "trim", Vector3(0, y, z + 0.008), Vector3(gw - 0.05, 0.016, 0.006))
		if extras.has("grille_surround"):
			for y in [gy - gh * 0.5, gy + gh * 0.5, gy]:
				_box(groups, "metal", Vector3(0, float(y), z + 0.008), Vector3(gw + 0.04, 0.024, 0.008))
			for x in [-gw * 0.5, gw * 0.5]:
				_box(groups, "metal", Vector3(float(x), gy, z + 0.008), Vector3(0.024, gh, 0.008))
		if extras.has("grille_bar"):
			_box(groups, "metal", Vector3(0, gy, z + 0.008), Vector3(gw - 0.04, 0.03, 0.008))
		var intake: Array = spec.intake
		if intake.size() == 3:
			_box(groups, "trim", Vector3(0, float(intake[2]), z + proud - 0.002), Vector3(float(intake[0]), float(intake[1]), 0.004))
	else:
		# On a bumper the plate is a 4mm skin on the bumper face; otherwise it
		# is set into the fascia. Either way it never passes the overall extent.
		var plate: Array = spec.plate
		var plate_y: float = plate[0]
		var on_bumper := plate_y > y0 and plate_y < y1
		var plate_z := z - proud + 0.002 if on_bumper else z - 0.002
		_box(groups, str(plate[1]), Vector3(0, plate_y, plate_z), Vector3(0.30, 0.15, 0.004 if on_bumper else 0.010))

static func _side_details(groups: Dictionary, kind: String) -> void:
	var c := Catalog.config(kind)
	var half := float(c.width) * 0.5
	for seam in c.seams:
		var z: float = seam[0]
		for side in _sides(int(seam[1])):
			var y0 := Catalog.bottom(kind, z) + 0.06
			var y1 := Catalog.upper(kind, z) - 0.05
			if y1 - y0 > 0.05:
				_box(groups, "trim", Vector3(side * (Catalog.half_width(kind, z) + 0.004), (y0 + y1) * 0.5, z), Vector3(0.008, y1 - y0, 0.012))
	for seam in c.tall_seams:
		var z: float = seam[0]
		var g := Catalog.greenhouse_at(kind, z)
		var y0: float = float(g.base) + 0.02
		var y1: float = float(g.top) - 0.12
		if y1 - y0 < 0.1:
			continue
		for side in _sides(int(seam[1])):
			var a := _glass_point(g, y0, side) + Vector3(side * -0.006, 0, 0)
			var b := _glass_point(g, y1, side) + Vector3(side * -0.006, 0, 0)
			_bar(groups, "trim", a, b, 0.008, 0.012)
	for handle in c.handles:
		var z: float = handle[0]
		var y := Catalog.upper(kind, z) - 0.13
		for side in _sides(int(handle[1])):
			_box(groups, "trim", Vector3(side * (Catalog.half_width(kind, z) + 0.012), y, z), Vector3(0.024, 0.032, 0.13))
	var strip: Dictionary = c.strip
	if not strip.is_empty():
		var arch: float = float(c.wheel_radius) + float(c.arch_gap)
		var z0: float = float(c.rear_axle) + arch + 0.06
		var z1: float = float(c.front_axle) - arch - 0.06
		for side in [-1.0, 1.0]:
			_box(groups, str(strip.material), Vector3(side * (half + 0.006), float(strip.y), (z0 + z1) * 0.5), Vector3(0.016, 0.045, z1 - z0))
	var mirror: Dictionary = c.mirror
	var mz: float = mirror.z
	var extent: Array = mirror["size"]
	var size := Vector3(float(extent[0]), float(extent[1]), float(extent[2]))
	var mg := Catalog.greenhouse_at(kind, mz)
	var my := Catalog.upper(kind, mz) + 0.07 + size.y * 0.5
	var head_x := half + 0.035 - size.x * 0.5
	var inner: float = float(mg.base_half)
	var arm := head_x - size.x * 0.5 - inner
	for side in [-1.0, 1.0]:
		_box(groups, "trim", Vector3(float(side) * head_x, my, mz), size)
		_fascia_skin(groups, "metal", Vector3(float(side) * head_x, my, mz - size.z * 0.5 - 0.001), size.x * 0.72, size.y * 0.72, -1.0)
		if arm > 0.01:
			_box(groups, "trim", Vector3(float(side) * (inner + arm * 0.5), Catalog.upper(kind, mz) + 0.05, mz), Vector3(arm + 0.02, 0.03, 0.05))

## Visible fender lip follows the very same sampled opening as the shell;
## the skirted rear of the long sedan is deliberately left uninterrupted.
static func _panel_details(groups: Dictionary, kind: String) -> void:
	var c := Catalog.config(kind)
	var radius: float = float(c.wheel_radius) + float(c.arch_gap)
	for axle in [float(c.front_axle), float(c.rear_axle)]:
		if axle == float(c.rear_axle) and float(c.rear_skirt) > 0.0:
			continue
		var samples := _stations(kind, axle - radius, axle + radius)
		for side in [-1.0, 1.0]:
			for i in range(1, samples.size()):
				var edge: Array[Vector3] = []
				for z in [samples[i - 1], samples[i]]:
					var ring := _lower_ring(kind, z)
					var a: Vector3 = ring[1]
					var b: Vector3 = ring[2]
					var t := minf(0.032 / maxf(b.y - a.y, 0.001), 0.8)
					var p := a.lerp(b, t)
					if c.extras.has("bed") and z < float(c.cab_back):
						a.x = -Catalog.half_width(kind, z)
						p.x = a.x
					edge.append(Vector3(side * absf(a.x) + side * 0.002, a.y, z))
					edge.append(Vector3(side * absf(p.x) + side * 0.002, p.y, z))
				_poly(groups, "paint", [edge[0], edge[2], edge[3], edge[1]], _shade(0.68), Vector3(side, 0.15, 0))
	# The hood shut lines follow the changing deck height; no raised box hood.
	var greenhouse: Array = c.greenhouse
	var hood_start: float = float(greenhouse[greenhouse.size() - 1][0]) + 0.035
	var hood_end := Catalog.body_front(kind) - 0.08
	if hood_end > hood_start + 0.10:
		var samples := _stations(kind, hood_start, hood_end)
		for side in [-1.0, 1.0]:
			for i in range(1, samples.size()):
				var a := Vector3(side * Catalog.half_width(kind, samples[i - 1]) * 0.68, Catalog.upper(kind, samples[i - 1]) + 0.003, samples[i - 1])
				var b := Vector3(side * Catalog.half_width(kind, samples[i]) * 0.68, Catalog.upper(kind, samples[i]) + 0.003, samples[i])
				_poly(groups, "trim", [a, b, b + Vector3(0.007, 0, 0), a + Vector3(0.007, 0, 0)], WHITE, Vector3.UP)
	var base := Catalog.greenhouse_station(kind, greenhouse.size() - 1)
	var roof := Catalog.greenhouse_station(kind, greenhouse.size() - 2)
	var low := Vector3(0, float(base.top), float(base.z)).lerp(Vector3(0, float(roof.top), float(roof.z)), 0.19)
	var high := Vector3(0, float(base.top), float(base.z)).lerp(Vector3(0, float(roof.top), float(roof.z)), 0.28)
	for side in [-1.0, 1.0]:
		var a := low + Vector3(side * 0.12, 0.013, 0.015)
		var b := high + Vector3(side * float(base.top_half) * 0.64, 0.013, 0.015)
		_poly(groups, "trim", [a, b, b + Vector3(0, 0.012, 0), a + Vector3(0, 0.012, 0)], WHITE, Vector3(0, 1, 1))

static func _sides(selector: int) -> Array[float]:
	var result: Array[float] = [-1.0, 1.0]
	if selector < 0:
		result = [-1.0]
	elif selector > 0:
		result = [1.0]
	return result

static func _bed(groups: Dictionary, kind: String) -> void:
	var c := Catalog.config(kind)
	var s: Dictionary = c.shades
	var bed: Dictionary = c.bed
	var floor_y: float = bed["floor"]
	var wall: float = bed["wall"]
	var rear := Catalog.body_rear(kind)
	var front: float = float(c.cab_back) - 0.04
	var inner_shade := _shade(0.62)
	for side in [-1.0, 1.0]:
		var rings: Array = []
		for z in _stations(kind, rear, front):
			var hw := Catalog.half_width(kind, z)
			var top := Catalog.upper(kind, z)
			var ys := _profile_heights(Catalog.bottom(kind, z), float(c.accent_y), top)
			var inner := hw - wall
			rings.append([Vector3(side * hw * 0.97, ys[0], z), Vector3(side * hw, ys[1], z), Vector3(side * hw, ys[2], z),
				Vector3(side * hw, ys[4], z), Vector3(side * hw * 0.99, top, z), Vector3(side * inner, top, z), Vector3(side * inner, floor_y, z)])
		var colors: Array[Color] = [_shade(float(s.rocker)), _shade(float(s.lower)), WHITE, WHITE, WHITE, inner_shade, _shade(float(s.under))]
		_loft(groups, "paint", rings, colors, WHITE, WHITE)
	var hw_mid := float(c.width) * 0.5 - wall
	var rail := Catalog.upper(kind, (rear + front) * 0.5)
	# 40mm floor slab stays above the rear tyre tops (2 x radius) inside the tubs.
	_box(groups, "trim", Vector3(0, floor_y - 0.02, (rear + front) * 0.5), Vector3(hw_mid * 2.0, 0.04, front - rear - 0.04))
	_box(groups, "paint", Vector3(0, (floor_y + rail) * 0.5, front - 0.03), Vector3(hw_mid * 2.0, rail - floor_y, 0.06), inner_shade)
	var tailgate_bottom := floor_y - 0.05
	_box(groups, "paint", Vector3(0, (tailgate_bottom + rail - 0.01) * 0.5, rear + 0.025), Vector3(hw_mid * 2.0 - 0.004, rail - 0.01 - tailgate_bottom, 0.05))
	_box(groups, "trim", Vector3(0, rail - 0.07, rear - 0.003), Vector3(0.20, 0.04, 0.008))
	var arch: float = float(c.wheel_radius) + float(c.arch_gap)
	var tub_top: float = float(c.wheel_radius) + arch + 0.03
	for side in [-1.0, 1.0]:
		_box(groups, "paint", Vector3(side * (hw_mid - 0.10), (floor_y + tub_top) * 0.5, float(c.rear_axle)),
			Vector3(0.20, tub_top - floor_y, arch * 1.8), inner_shade)
	var sill: float = c.sill
	_box(groups, "trim", Vector3(0, (sill + tailgate_bottom) * 0.5, (rear + 0.15 + float(c.cab_back)) * 0.5),
		Vector3(1.0, tailgate_bottom - sill, float(c.cab_back) - rear - 0.15))

static func _rear_doors(groups: Dictionary, kind: String) -> void:
	var rear := Catalog.body_rear(kind)
	var low := Catalog.bottom(kind, rear) + 0.06
	var top := Catalog.upper(kind, rear)
	_box(groups, "trim", Vector3(0, (low + top) * 0.5, rear - 0.003), Vector3(0.012, top - low, 0.008))
	var base := Catalog.greenhouse_station(kind, 0)
	var roof := Catalog.greenhouse_station(kind, 1)
	var a := Vector3(0, float(base.top) - 0.02, float(base.z) - 0.006)
	var b := Vector3(0, float(roof.top) - 0.07, float(roof.z) - 0.006)
	_bar(groups, "trim", a, b, 0.012, 0.008)
	for side in [-1.0, 1.0]:
		_box(groups, "metal", Vector3(side * 0.07, top - 0.10, rear - 0.006), Vector3(0.10, 0.03, 0.012))

static func _roof_rails(groups: Dictionary, kind: String) -> void:
	var c := Catalog.config(kind)
	var height: float = c.height
	for side in [-1.0, 1.0]:
		var z0 := -1.70
		var z1 := 0.10
		var g := Catalog.greenhouse_at(kind, (z0 + z1) * 0.5)
		var x: float = side * (float(g.top_half) * 0.95 - 0.03)
		_box(groups, "trim", Vector3(x, height - 0.0175, (z0 + z1) * 0.5), Vector3(0.035, 0.035, z1 - z0))
		for z in [z0 + 0.05, z1 - 0.05]:
			_box(groups, "trim", Vector3(x, height - 0.03, float(z)), Vector3(0.05, 0.03, 0.10))

static func _spare(groups: Dictionary, kind: String) -> void:
	var c := Catalog.config(kind)
	var rear := Catalog.body_rear(kind)
	var radius := 0.31
	var center := Vector3(0, 0.80, rear - 0.115)
	# Wheel axis is local X; turn it to point along the body (-Z/+Z).
	var pose := Transform3D(Basis(Vector3.UP, PI * 0.5), center)
	_tire(groups, pose, radius, 0.10, NEAR_SEGMENTS, c.wheel_style, true)
	_box(groups, "trim", Vector3(0, center.y, rear - 0.008), Vector3(0.12, 0.12, 0.016))

static func _hatch_spoiler(groups: Dictionary, kind: String) -> void:
	var roof := Catalog.greenhouse_station(kind, 1)
	_box(groups, "paint", Vector3(0, float(roof.top) - 0.005, float(roof.z) - 0.03),
		Vector3(float(roof.top_half) * 1.80, 0.035, 0.16), _shade(float(Catalog.config(kind).shades.roof)))

static func body(kind: String) -> Dictionary:
	var c := Catalog.config(kind)
	var groups: Dictionary = {}
	var extras: Array = c.extras
	var front := Catalog.body_front(kind)
	var rear := Catalog.body_rear(kind)
	if extras.has("bed"):
		_lower_body(groups, kind, float(c.cab_back), front)
		_bed(groups, kind)
	else:
		_lower_body(groups, kind, rear, front)
	_greenhouse(groups, kind)
	for span in c.windows:
		_side_window(groups, kind, float(span[0]), float(span[1]))
	_end_glass(groups, kind, true, 0.10, 0.92, 0.05, false)
	if extras.has("bed"):
		_end_glass(groups, kind, false, 0.30, 0.86, 0.20, false)
	elif extras.has("rear_doors"):
		_end_glass(groups, kind, false, 0.42, 0.88, 0.06, true)
	else:
		_end_glass(groups, kind, false, 0.12, 0.90, 0.06, false)
	_fascia(groups, kind, true)
	_fascia(groups, kind, false)
	_side_details(groups, kind)
	_panel_details(groups, kind)
	if extras.has("rear_doors"):
		_rear_doors(groups, kind)
	if extras.has("roof_rails"):
		_roof_rails(groups, kind)
	if extras.has("spare"):
		_spare(groups, kind)
	if extras.has("hatch_spoiler"):
		_hatch_spoiler(groups, kind)
	return groups

# --- Wheels -----------------------------------------------------------------

## One road wheel in the legacy wheel frame: axis local X, centred at origin.
static func wheel(kind: String, segments: int) -> Dictionary:
	var c := Catalog.config(kind)
	var groups: Dictionary = {}
	_tire(groups, Transform3D.IDENTITY, float(c.wheel_radius), float(c.tire_half_width), segments, c.wheel_style, segments >= NEAR_SEGMENTS)
	return groups

static func _tire(groups: Dictionary, pose: Transform3D, radius: float, half: float, segments: int, style: Dictionary, detailed: bool) -> void:
	var lip := 0.012
	var profile: Array[Vector2] = []
	if detailed:
		profile.assign([Vector2(-(half - lip), radius * 0.64), Vector2(-half, radius * 0.70), Vector2(-half, radius * 0.86),
			Vector2(-half * 0.72, radius), Vector2(half * 0.72, radius), Vector2(half, radius * 0.86),
			Vector2(half, radius * 0.70), Vector2(half - lip, radius * 0.64)])
	else:
		profile.assign([Vector2(-(half - lip), radius * 0.64), Vector2(-half, radius * 0.86), Vector2(-half * 0.70, radius),
			Vector2(half * 0.70, radius), Vector2(half, radius * 0.86), Vector2(half - lip, radius * 0.64)])
	for i in range(1, profile.size()):
		var p := profile[i - 1]
		var q := profile[i]
		var d := q - p
		var n2 := Vector2(-d.y, d.x).normalized()
		for j in segments:
			var a0 := float(j) * TAU / segments
			var a1 := float(j + 1) * TAU / segments
			var points: Array[Vector3] = [_spin(p, a0), _spin(q, a0), _spin(q, a1), _spin(p, a1)]
			var normals: Array[Vector3] = [_spin(n2, a0), _spin(n2, a0), _spin(n2, a1), _spin(n2, a1)]
			_smooth_quad(groups, "trim", pose, points, normals)
	var rim_r := radius * 0.64
	var hub_r := radius * 0.24
	for side in [-1.0, 1.0]:
		var x: float = side * (half - lip)
		var out := pose.basis * Vector3(side, 0, 0)
		if not detailed:
			for j in segments:
				_poly(groups, str(style.rim), _disc_tri(pose, x, rim_r, j, segments), WHITE, out)
			continue
		for j in segments:
			var a0 := float(j) * TAU / segments
			var a1 := float(j + 1) * TAU / segments
			# Dished wheel cover, with the outer bead rolled toward the sidewall.
			# This replaces the flat disc with one extra inexpensive annular band.
			var well_x: float = x - side * 0.014
			_poly(groups, str(style.rim), [pose * _spin(Vector2(well_x, hub_r), a0), pose * _spin(Vector2(well_x, rim_r * 0.87), a0),
				pose * _spin(Vector2(well_x, rim_r * 0.87), a1), pose * _spin(Vector2(well_x, hub_r), a1)], WHITE, out)
			_poly(groups, str(style.rim), [pose * _spin(Vector2(well_x, rim_r * 0.87), a0), pose * _spin(Vector2(x, rim_r), a0),
				pose * _spin(Vector2(x, rim_r), a1), pose * _spin(Vector2(well_x, rim_r * 0.87), a1)], WHITE, out)
			_poly(groups, str(style.hub), _disc_tri(pose, x + side * 0.004, hub_r, j, segments), WHITE, out)
		var slots: int = style.slot_count
		for k in slots:
			var angle := (float(k) + 0.5) * TAU / slots
			var w := 0.30 / float(slots) * PI * 0.5
			var sx: float = x - side * 0.010
			_poly(groups, str(style.slots), [pose * _spin(Vector2(sx, radius * 0.34), angle - w), pose * _spin(Vector2(sx, radius * 0.56), angle - w),
				pose * _spin(Vector2(sx, radius * 0.56), angle + w), pose * _spin(Vector2(sx, radius * 0.34), angle + w)], WHITE, out)

static func _disc_tri(pose: Transform3D, x: float, radius: float, j: int, segments: int) -> Array:
	var a0 := float(j) * TAU / segments
	var a1 := float(j + 1) * TAU / segments
	return [pose * Vector3(x, 0, 0), pose * _spin(Vector2(x, radius), a0), pose * _spin(Vector2(x, radius), a1)]

## Profile point (x along the axle, r radial) at angle a, legacy wheel frame.
static func _spin(p: Vector2, a: float) -> Vector3:
	return Vector3(p.x, sin(a) * p.y, cos(a) * p.y)
