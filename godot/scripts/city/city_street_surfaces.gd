class_name CityStreetSurfaces
extends RefCounted
## Exact source pavement polygons, clipped into small tiles by the city exporter.
## One immutable index per process; placement never guesses from road offsets.
const DATA := "res://assets/data/pen_lucy_street_surfaces.json"
const CELL := 64.0
static var _loaded := false
static var _cells: Dictionary = {}
static var _counts: Dictionary = {}

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(DATA):
		push_warning("Street fixtures require exact pavement metadata: " + DATA)
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	if not data is Dictionary or int(data.get("version", 0)) != 1:
		return
	for kind in ["sidewalk", "road"]:
		_cells[kind] = {}
		_counts[kind] = 0
		for record in data.get("surfaces", {}).get(kind, []):
			var polygon := _ring(record.get("polygon", []))
			if polygon.size() < 3:
				continue
			var holes: Array[PackedVector2Array] = []
			for ring in record.get("holes", []):
				holes.append(_ring(ring))
			var bounds := Rect2(polygon[0], Vector2.ZERO)
			for point in polygon:
				bounds = bounds.expand(point)
			var decoded := {"polygon": polygon, "holes": holes, "bounds": bounds.grow(0.002)}
			for x in range(floori(bounds.position.x / CELL), floori(bounds.end.x / CELL) + 1):
				for z in range(floori(bounds.position.y / CELL), floori(bounds.end.y / CELL) + 1):
					var key := Vector2i(x, z)
					if not _cells[kind].has(key):
						_cells[kind][key] = []
					_cells[kind][key].append(decoded)
			_counts[kind] += 1

static func _ring(values: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in values:
		result.append(Vector2(float(point[0]), float(point[1])))
	return result

static func contains(kind: String, at: Vector3) -> bool:
	_load()
	var point := Vector2(at.x, at.z)
	var cell := Vector2i(floori(at.x / CELL), floori(at.z / CELL))
	for record in _cells.get(kind, {}).get(cell, []):
		if not record.bounds.has_point(point) or not Geometry2D.is_point_in_polygon(point, record.polygon):
			continue
		var in_hole := false
		for hole in record.holes:
			if Geometry2D.is_point_in_polygon(point, hole):
				in_hole = true
				break
		if not in_hole:
			return true
	return false

static func circle_clear(kind: String, at: Vector3, radius: float) -> bool:
	if not contains(kind, at):
		return false
	for i in 12:
		var angle := float(i) * TAU / 12.0
		if not contains(kind, at + Vector3(cos(angle), 0, sin(angle)) * radius):
			return false
	return true

static func rectangle_clear(kind: String, at: Vector3, across: Vector3, forward: Vector3, half: Vector2) -> bool:
	for x in [-1.0, 0.0, 1.0]:
		for z in [-1.0, 0.0, 1.0]:
			if not contains(kind, at + across * half.x * float(x) + forward * half.y * float(z)):
				return false
	return true

static func get_status() -> Dictionary:
	_load()
	return {"available": not _counts.is_empty(), "polygons": _counts.duplicate(), "cell_size": CELL}
