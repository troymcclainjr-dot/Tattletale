extends RefCounted
## Shared vector symbols for the phone, map key, full map and radar. Shapes are
## cached as small triangle templates and flushed as one colored triangle array
## per canvas, so dozens of map symbols cost one draw call, never font glyphs,
## emoji or textures.
const INK := Color("101d20")
const CATEGORIES := ["police", "fire", "hospital", "court", "shop", "food", "service", "studio", "park", "landmark"]
const COLORS := {
	"police": Color("7cbcff"), "fire": Color("ff967d"), "hospital": Color("d4a1ff"),
	"court": Color("e5d4a2"), "shop": Color("e4b47c"), "food": Color("f29e6d"),
	"service": Color("b7c9d6"), "studio": Color("dda6d1"), "park": Color("81d6b1"),
	"landmark": Color("f2d24a"), "contact": Color("70e0da"), "you": Color("fff6df"),
	"bicycle": Color("8ce7ef"), "car": Color("8ce7ef"), "destination": Color("f2d24a"),
}
const NAMES := {
	"police": "Police", "fire": "Fire", "hospital": "Hospital", "court": "Courthouse",
	"shop": "Shop", "food": "Food", "service": "Service", "studio": "Studio",
	"park": "Park", "landmark": "Landmark", "contact": "Neighbor", "you": "You",
	"bicycle": "Your bicycle", "car": "Your car", "destination": "Destination",
}
## Sports courts on the map: muted blue-green, never the route's yellow.
const SPORTS_COURT := Color("456f6b")
const SPORTS_COURT_EDGE := Color("79a39b")
const FEATHER := 0.9
static var _templates: Dictionary = {}

static func category_for(kind: String) -> String:
	match kind:
		"police", "fire", "hospital", "studio", "park", "landmark":
			return kind
		"courthouse", "court":
			return "court"
		"liquor", "corner_store", "pawnshop", "market", "variety", "books", "gun_store", "weed_store":
			return "shop"
		"takeout", "restaurant", "cafe", "food":
			return "food"
	return "service"

static func color_for(category: String) -> Color:
	return COLORS.get(category, COLORS.service)

## Compact place name for a single hover/selection caption.
static func short_name(label: String, limit := 20) -> String:
	var text := label.strip_edges()
	if text.length() > limit:
		for prefix in ["Pen Lucy ", "The "]:
			if text.begins_with(prefix):
				text = text.substr(prefix.length())
	if text.length() <= limit:
		return text
	var cut := text.substr(0, limit)
	var space := cut.rfind(" ")
	if space >= limit / 2:
		cut = cut.substr(0, space)
	return cut.strip_edges() + "..."

## Expanded triangle list (three vertices per triangle) with vertex colors.
class Shapes:
	var points := PackedVector2Array()
	var colors := PackedColorArray()

	func triangle(a: Vector2, b: Vector2, c: Vector2, ca: Color, cb: Color, cc: Color) -> void:
		points.append(a)
		points.append(b)
		points.append(c)
		colors.append(ca)
		colors.append(cb)
		colors.append(cc)

	func quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color) -> void:
		triangle(a, b, c, color, color, color)
		triangle(a, c, d, color, color, color)

	## Filled disc; `feather` adds a transparent rim instead of antialiasing.
	func circle(at: Vector2, r: float, color: Color, feather := 0.0) -> void:
		var count := clampi(int(r * 1.4) + 10, 12, 32)
		var faded := Color(color, 0.0)
		for i in count:
			var a := TAU * i / count
			var b := TAU * (i + 1) / count
			var p := at + Vector2(cos(a), sin(a)) * r
			var q := at + Vector2(cos(b), sin(b)) * r
			triangle(at, p, q, color, color, color)
			if feather > 0.0:
				var pf := at + Vector2(cos(a), sin(a)) * (r + feather)
				var qf := at + Vector2(cos(b), sin(b)) * (r + feather)
				triangle(p, pf, qf, color, faded, faded)
				triangle(p, qf, q, color, faded, color)

	func polygon(shape: PackedVector2Array, color: Color) -> void:
		var indices := Geometry2D.triangulate_polygon(shape)
		for i in range(0, indices.size(), 3):
			triangle(shape[indices[i]], shape[indices[i + 1]], shape[indices[i + 2]], color, color, color)

	func rect(area: Rect2, color: Color) -> void:
		quad(area.position, Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y), color)

	func rect_outline(area: Rect2, color: Color, width: float) -> void:
		var corners := [area.position, Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y)]
		for i in 4:
			line(corners[i], corners[(i + 1) % 4], color, width)

	func line(a: Vector2, b: Vector2, color: Color, width: float) -> void:
		if a.is_equal_approx(b):
			return
		var n := (b - a).orthogonal().normalized() * width * 0.5
		var along := (b - a).normalized() * width * 0.25
		quad(a - along + n, b + along + n, b + along - n, a - along - n, color)

	func polyline(pts: PackedVector2Array, color: Color, width: float) -> void:
		for i in range(1, pts.size()):
			line(pts[i - 1], pts[i], color, width)

	func arc(at: Vector2, r: float, from: float, to: float, color: Color, width: float) -> void:
		var count := clampi(int(r * absf(to - from) * 0.4) + 6, 8, 40)
		var inner := r - width * 0.5
		var outer := r + width * 0.5
		for i in count:
			var a := lerpf(from, to, float(i) / count)
			var b := lerpf(from, to, float(i + 1) / count)
			var da := Vector2(cos(a), sin(a))
			var db := Vector2(cos(b), sin(b))
			quad(at + da * inner, at + da * outer, at + db * outer, at + db * inner, color)

	func append(other: Shapes, offset := Vector2.ZERO) -> void:
		points.append_array(other.points if offset == Vector2.ZERO else Transform2D(0.0, offset) * other.points)
		colors.append_array(other.colors)

	func clear() -> void:
		points.clear()
		colors.clear()

	## One draw command for everything queued on this canvas item.
	func flush(ci: CanvasItem) -> int:
		var count := points.size()
		if count < 3:
			clear()
			return 0
		RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), Shapes.sequence(count), points, colors)
		clear()
		return count / 3

	static var _sequence := PackedInt32Array()
	## Shared 0..n-1 index list: expanded triangles need no per-symbol indices.
	static func sequence(count: int) -> PackedInt32Array:
		if _sequence.size() < count:
			var start := _sequence.size()
			_sequence.resize(maxi(count, start * 2))
			for i in range(start, _sequence.size()):
				_sequence[i] = i
		return _sequence.slice(0, count)

## Cached map badge at the origin: ink rim, category disc, ink symbol.
static func badge(category: String, radius: float, fill := Color.TRANSPARENT, ring := false) -> Shapes:
	var color := fill if fill.a > 0.0 else color_for(category)
	var key := "badge|%s|%.1f|%s|%s" % [category, radius, color.to_html(), ring]
	if not _templates.has(key):
		var shapes := Shapes.new()
		if ring:
			shapes.arc(Vector2.ZERO, radius + 4.0, 0.0, TAU, COLORS.you, 2.0)
		shapes.circle(Vector2.ZERO, radius + 1.5, INK, FEATHER)
		shapes.circle(Vector2.ZERO, radius, color)
		glyph_into(shapes, category, Vector2.ZERO, radius * 0.62, INK)
		_templates[key] = shapes
	return _templates[key]

## Cached disc with an optional rim (neighbors, marker backgrounds).
static func dot(radius: float, color: Color, rim := Color.TRANSPARENT) -> Shapes:
	var key := "dot|%.1f|%s|%s" % [radius, color.to_html(), rim.to_html()]
	if not _templates.has(key):
		var shapes := Shapes.new()
		if rim.a > 0.0:
			shapes.circle(Vector2.ZERO, radius + 1.5, rim, FEATHER)
			shapes.circle(Vector2.ZERO, radius, color)
		else:
			shapes.circle(Vector2.ZERO, radius, color, FEATHER)
		_templates[key] = shapes
	return _templates[key]

## Cached mission destination: ink disc, ring and centre.
static func target(color: Color) -> Shapes:
	var key := "target|" + color.to_html()
	if not _templates.has(key):
		var shapes := Shapes.new()
		shapes.circle(Vector2.ZERO, 10.0, INK, FEATHER)
		shapes.arc(Vector2.ZERO, 8.0, 0.0, TAU, color, 3.0)
		shapes.circle(Vector2.ZERO, 3.0, color)
		_templates[key] = shapes
	return _templates[key]

## Cached symbol at the origin.
static func glyph(kind: String, r: float, color: Color) -> Shapes:
	var key := "glyph|%s|%.1f|%s" % [kind, r, color.to_html()]
	if not _templates.has(key):
		var shapes := Shapes.new()
		glyph_into(shapes, kind, Vector2.ZERO, r, color)
		_templates[key] = shapes
	return _templates[key]

## Immediate helpers for single symbols (phone tiles, map key): one command each.
static func draw_badge(ci: CanvasItem, category: String, at: Vector2, radius: float, fill := Color.TRANSPARENT, ring := false) -> void:
	var shapes := Shapes.new()
	shapes.append(badge(category, radius, fill, ring), at)
	shapes.flush(ci)

static func draw_glyph(ci: CanvasItem, kind: String, at: Vector2, r: float, color: Color) -> void:
	var shapes := Shapes.new()
	shapes.append(glyph(kind, r, color), at)
	shapes.flush(ci)

static func _shape(at: Vector2, r: float, pts: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for p in pts:
		result.append(at + Vector2(p[0], p[1]) * r)
	return result

## One symbol inside a box of half-extent r around `at`.
static func glyph_into(s: Shapes, kind: String, at: Vector2, r: float, color: Color) -> void:
	var w := maxf(1.2, r * 0.22)
	match kind:
		"police":
			s.polygon(_shape(at, r, [[-0.75, -0.85], [0.75, -0.85], [0.75, 0.1], [0, 0.95], [-0.75, 0.1]]), color)
		"fire":
			s.polygon(_shape(at, r, [[0, -1.0], [0.5, -0.2], [0.7, 0.35], [0.35, 0.9], [-0.35, 0.9], [-0.7, 0.35], [-0.5, -0.15], [-0.2, 0.1]]), color)
		"hospital":
			s.rect(Rect2(at + Vector2(-0.28, -0.85) * r, Vector2(0.56, 1.7) * r), color)
			s.rect(Rect2(at + Vector2(-0.85, -0.28) * r, Vector2(1.7, 0.56) * r), color)
		"court":
			s.polygon(_shape(at, r, [[-0.95, -0.4], [0, -1.0], [0.95, -0.4]]), color)
			for x in [-0.6, 0.0, 0.6]:
				s.rect(Rect2(at + Vector2(x - 0.13, -0.3) * r, Vector2(0.26, 0.95) * r), color)
			s.rect(Rect2(at + Vector2(-0.95, 0.7) * r, Vector2(1.9, 0.28) * r), color)
		"shop":
			s.rect(Rect2(at + Vector2(-0.75, -0.3) * r, Vector2(1.5, 1.2) * r), color)
			s.arc(at + Vector2(0, -0.3) * r, 0.42 * r, PI, TAU, color, w)
		"food":
			s.polygon(_shape(at, r, [[-0.65, -0.45], [0.65, -0.45], [0.42, 0.95], [-0.42, 0.95]]), color)
			s.rect(Rect2(at + Vector2(-0.8, -0.75) * r, Vector2(1.6, 0.22) * r), color)
			s.line(at + Vector2(0.15, -0.75) * r, at + Vector2(0.4, -1.05) * r, color, w)
		"service":
			for side in [-1.0, 1.0]:
				s.arc(at + Vector2(side * 0.42, 0.55) * r, 0.3 * r, 0.0, TAU, color, w)
				s.line(at + Vector2(side * 0.3, 0.3) * r, at + Vector2(-side * 0.45, -0.95) * r, color, w * 1.2)
		"studio":
			s.circle(at + Vector2(-0.3, 0.55) * r, 0.36 * r, color)
			s.line(at + Vector2(0.03, 0.55) * r, at + Vector2(0.03, -0.9) * r, color, w * 1.2)
			s.line(at + Vector2(0.03, -0.9) * r, at + Vector2(0.6, -0.55) * r, color, w * 1.2)
		"park":
			s.circle(at + Vector2(0, -0.25) * r, 0.62 * r, color)
			s.rect(Rect2(at + Vector2(-0.13, 0.2) * r, Vector2(0.26, 0.8) * r), color)
		"landmark":
			s.polygon(_shape(at, r, [[0, -0.95], [0.7, 0], [0, 0.95], [-0.7, 0]]), color)
		"contact", "contacts":
			s.circle(at + Vector2(0, -0.45) * r, 0.36 * r, color)
			s.polygon(_shape(at, r, [[-0.75, 0.95], [-0.6, 0.25], [0, 0.0], [0.6, 0.25], [0.75, 0.95]]), color)
		"camera":
			s.rect(Rect2(at + Vector2(-0.95, -0.5) * r, Vector2(1.9, 1.35) * r), color)
			s.rect(Rect2(at + Vector2(-0.35, -0.75) * r, Vector2(0.7, 0.3) * r), color)
			s.circle(at + Vector2(0, 0.17) * r, 0.42 * r, INK)
			s.circle(at + Vector2(0, 0.17) * r, 0.22 * r, color)
		"photos":
			s.rect_outline(Rect2(at + Vector2(-0.9, -0.75) * r, Vector2(1.8, 1.5) * r), color, w)
			s.polygon(_shape(at, r, [[-0.75, 0.62], [-0.2, -0.05], [0.2, 0.35], [0.45, 0.1], [0.75, 0.62]]), color)
			s.circle(at + Vector2(0.4, -0.35) * r, 0.16 * r, color)
		"cases":
			s.polygon(_shape(at, r, [[-0.95, -0.7], [-0.25, -0.7], [-0.1, -0.5], [0.95, -0.5], [0.95, 0.8], [-0.95, 0.8]]), color)
		"map":
			s.polygon(_shape(at, r, [[-0.95, -0.7], [-0.32, -0.95], [-0.32, 0.7], [-0.95, 0.95]]), color)
			s.polygon(_shape(at, r, [[-0.22, -0.92], [0.22, -0.72], [0.22, 0.92], [-0.22, 0.72]]), color)
			s.polygon(_shape(at, r, [[0.32, -0.7], [0.95, -0.95], [0.95, 0.7], [0.32, 0.95]]), color)
		"back":
			s.polyline(_shape(at, r, [[0.35, -0.75], [-0.4, 0], [0.35, 0.75]]), color, w * 1.4)
		"home":
			s.arc(at, 0.7 * r, 0.0, TAU, color, w * 1.3)
		"close":
			s.line(at + Vector2(-0.6, -0.6) * r, at + Vector2(0.6, 0.6) * r, color, w * 1.4)
			s.line(at + Vector2(0.6, -0.6) * r, at + Vector2(-0.6, 0.6) * r, color, w * 1.4)
		"destination":
			s.arc(at, 0.8 * r, 0.0, TAU, color, w * 1.4)
			s.circle(at, 0.3 * r, color)
		"bicycle":
			for side in [-1.0, 1.0]:
				s.arc(at + Vector2(side * 0.55, 0.3) * r, 0.38 * r, 0.0, TAU, color, w)
			s.polyline(_shape(at, r, [[-0.55, 0.3], [-0.2, -0.35], [0.2, 0.3], [-0.55, 0.3], [0.3, -0.35], [0.55, 0.3]]), color, w)
			s.line(at + Vector2(0.3, -0.35) * r, at + Vector2(0.2, -0.7) * r, color, w)
			s.line(at + Vector2(0.2, -0.7) * r, at + Vector2(0.55, -0.7) * r, color, w)
		"car":
			s.rect(Rect2(at + Vector2(-0.95, -0.55) * r, Vector2(1.9, 1.1) * r), color)
			s.rect(Rect2(at + Vector2(-0.35, -0.42) * r, Vector2(0.7, 0.84) * r), INK)
		"north":
			s.polygon(_shape(at, r, [[0, -1.0], [0.55, 0.2], [0, -0.1], [-0.55, 0.2]]), color)
			letter_n_into(s, at + Vector2(0, 0.62) * r, r * 0.34, color, w)
		_:
			s.circle(at, 0.5 * r, color)

## A stroked "N" with no font: stable in the radar at every frame and DPI.
static func letter_n_into(s: Shapes, at: Vector2, half: float, color: Color, width := 1.6) -> void:
	s.polyline(PackedVector2Array([at + Vector2(-half * 0.7, half), at + Vector2(-half * 0.7, -half),
		at + Vector2(half * 0.7, half), at + Vector2(half * 0.7, -half)]), color, width)
