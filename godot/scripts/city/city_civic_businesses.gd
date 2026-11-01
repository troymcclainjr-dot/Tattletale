extends RefCounted
## Complete, static two-storey neighborhood storefronts. Local ground is y=0;
## street frontage faces +Z. Six batched finishes and one physical sign per shop.
const Kit := preload("res://scripts/city/city_civic_mesh_kit.gd")

static func build(entry: Dictionary) -> Node3D:
	var kit := Kit.new(str(entry.get("id", "NeighborhoodShop")))
	var service: String = str(entry.get("service", "corner_store"))
	var variant := int(entry.get("variant", 0)) % 3
	var brick: Color = [Color("6e4941"), Color("875a46"), Color("786357")][variant]
	var accent := Color("395f58")
	if service == "studio":
		accent = Color("554367")
	elif service == "liquor":
		accent = Color("653e44")
	kit.material("brick", brick, 1)
	kit.material("stone", Color("b4a58c"), 2)
	kit.material("metal", Color("303c3f"), 6, 0.6)
	kit.material("glass", Color("304f56"), 0, 0.22)
	kit.material("accent", accent, 4)
	kit.material("detail", Color("d9bc79"), 6)
	var w := float(entry.get("width", 10.0))
	var d := float(entry.get("depth", 11.0))
	var foundation := maxf(0.45, float(entry.get("foundation_depth", 0.6)))
	var front := d * 0.5
	var wall := 0.26
	# Continuous foundation closes the removed export's terrain hole. The lower
	# storefront is constructed from piers and glazing, with proper wall returns.
	_foundation(kit, entry, w, d, foundation)
	kit.box(Vector3(-w * 0.5 + wall * 0.5, 1.6, 0), Vector3(wall, 3.2, d), "brick")
	kit.box(Vector3(w * 0.5 - wall * 0.5, 1.6, 0), Vector3(wall, 3.2, d), "brick")
	kit.box(Vector3(0, 1.6, -front + wall * 0.5), Vector3(w, 3.2, wall), "brick")
	kit.box(Vector3(0, 5.1, 0), Vector3(w, 3.8, d), "brick")
	kit.box(Vector3(0, 3.22, 0), Vector3(w + 0.12, 0.18, d + 0.12), "stone")
	kit.box(Vector3(0, 7.02, 0), Vector3(w + 0.16, 0.18, d + 0.16), "stone")
	kit.box(Vector3(0, 7.16, 0), Vector3(w - 0.32, 0.18, d - 0.32), "metal")
	for x in [-w * 0.5 + 0.18, w * 0.5 - 0.18]:
		kit.box(Vector3(x, 7.3, 0), Vector3(0.24, 0.42, d), "brick")
	for z in [-front + 0.16, front - 0.16]:
		kit.box(Vector3(0, 7.3, z), Vector3(w, 0.42, 0.24), "brick")
	kit.solid_box(Vector3(0, (7.5 - foundation) * 0.5, 0), Vector3(w, 7.5 + foundation, d))
	# Storefront frame, broad display bays, recessed door and a continuous sign
	# fascia belong to the building; nothing is stamped across existing windows.
	for x in [-w * 0.5 + 0.32, -0.83, 0.83, w * 0.5 - 0.32]:
		kit.box(Vector3(x, 1.53, front - 0.02), Vector3(0.22, 3.06, 0.3), "stone")
	for side in [-1.0, 1.0]:
		var bay_width := w * 0.5 - 1.3
		var bay_x: float = float(side) * (w * 0.25 + 0.35)
		kit.box(Vector3(bay_x, 0.37, front - 0.03), Vector3(bay_width, 0.74, 0.24), "accent")
		kit.box(Vector3(bay_x, 1.6, front - 0.065), Vector3(bay_width, 1.7, 0.12), "glass")
		for x in [bay_x - bay_width * 0.5, bay_x, bay_x + bay_width * 0.5]:
			kit.box(Vector3(x, 1.6, front + 0.015), Vector3(0.065, 1.8, 0.065), "metal")
		for y in [0.73, 2.47]:
			kit.box(Vector3(bay_x, y, front + 0.02), Vector3(bay_width, 0.075, 0.075), "metal")
		_display(kit, service, bay_x, front + 0.025, bay_width)
	kit.box(Vector3(0, 1.23, front - 0.06), Vector3(1.38, 2.46, 0.16), "metal")
	kit.box(Vector3(0, 1.46, front + 0.03), Vector3(1.13, 1.6, 0.05), "glass")
	kit.box(Vector3(0.44, 1.07, front + 0.09), Vector3(0.045, 0.42, 0.055), "detail")
	kit.box(Vector3(0, 2.86, front + 0.07), Vector3(w - 0.42, 0.64, 0.28), "accent")
	kit.box(Vector3(0, 2.48, front + 0.28), Vector3(w - 0.55, 0.1, 0.78), "metal")
	kit.box(Vector3(0, 2.42, front + 0.62), Vector3(w - 0.55, 0.16, 0.09), "accent")
	var subtitle := "DAILY GOODS  /  NEIGHBORHOOD MARKET"
	if service == "studio":
		subtitle = "RECORDING STUDIO"
	elif service == "liquor":
		subtitle = "WINE  /  BEER  /  SPIRITS"
	var title := str(entry.get("label", "Neighborhood Market")).to_upper()
	# Fit the longest line to the fascia rather than allowing projecting text.
	var pixel_size := minf(0.009, (w - 0.9) / (maxi(title.length(), subtitle.length()) * 24.0))
	kit.label(title + "\n" + subtitle, Vector3(0, 2.87, front + 0.222), 40, pixel_size)
	var windows := maxi(2, int(w / 2.6))
	for i in windows:
		var x := -w * 0.5 + w * float(i + 1) / float(windows + 1)
		_upper_window(kit, Vector3(x, 5.13, front + 0.04), 0.0)
		_upper_window(kit, Vector3(x, 5.13, -front - 0.04), PI)
	for side in [-1.0, 1.0]:
		for z in [-d * 0.23, d * 0.23]:
			_upper_window(kit, Vector3(side * (w * 0.5 + 0.04), 5.13, z), side * PI * 0.5)
	var rise := float(entry.get("entry_rise", 0.18))
	for step in 3:
		var top := -rise * float(step) / 3.0
		var height := foundation + 0.25
		var at := Vector3(0, top - height * 0.5, front + 0.125 + float(step) * 0.25)
		kit.box(at, Vector3(1.65, height, 0.25), "stone")
		kit.solid_box(at, Vector3(1.65, height, 0.25))
	# Rear service door and rooftop plant remain contained within the footprint.
	kit.box(Vector3(0, 1.12, -front - 0.025), Vector3(1.05, 2.24, 0.075), "metal")
	kit.box(Vector3(-w * 0.2, 7.42, -d * 0.16), Vector3(1.2, 0.45, 1.3), "metal")
	kit.cylinder(Vector3(w * 0.28, 7.6, -d * 0.25), 0.12, 0.8, "metal", 8)
	var result := kit.finish()
	result.set_meta("service", service)
	result.set_meta("source_mesh", str(entry.get("source_mesh", "")))
	result.set_meta("architecture_surfaces", 6)
	return result

static func _upper_window(kit, at: Vector3, yaw: float) -> void:
	var facing := Vector3(sin(yaw), 0, cos(yaw))
	kit.box(at, Vector3(1.38, 1.93, 0.14), "stone", yaw)
	kit.box(at + facing * 0.09, Vector3(1.13, 1.64, 0.075), "glass", yaw)
	kit.box(at + facing * 0.14, Vector3(0.06, 1.65, 0.05), "metal", yaw)
	kit.box(at + facing * 0.14, Vector3(1.14, 0.06, 0.05), "metal", yaw)
	kit.box(at + Vector3(0, -0.98, 0) + facing * 0.07, Vector3(1.5, 0.14, 0.28), "stone", yaw)

static func _display(kit, service: String, center: float, front: float, width: float) -> void:
	if service == "studio":
		# A quiet waveform motif inset in the display glazing identifies the studio.
		for i in 9:
			var height := 0.18 + 0.5 * absf(sin(float(i) * 1.23))
			kit.box(Vector3(center + (float(i) - 4.0) * width / 12.0, 1.5, front), Vector3(0.07, height, 0.045), "detail")
	elif service == "liquor":
		for i in 5:
			var x := center + (float(i) - 2.0) * width / 7.0
			kit.box(Vector3(x, 1.03, front), Vector3(0.14, 0.36, 0.05), "detail")
			kit.box(Vector3(x, 1.26, front), Vector3(0.06, 0.11, 0.05), "detail")
	else:
		for i in 3:
			var x := center + (float(i) - 1.0) * width / 4.5
			kit.box(Vector3(x, 0.98, front), Vector3(width / 5.0, 0.23, 0.07), "detail")

static func _foundation(kit, entry: Dictionary, w: float, d: float, depth: float) -> void:
	var vertices: Array = entry.get("foundation_polygon", [])
	if vertices.is_empty():
		kit.box(Vector3(0, -depth * 0.5, 0), Vector3(w, depth, d), "stone")
		return
	var at: Array = entry.get("position", [0, 0, 0])
	var yaw := float(entry.get("yaw", 0.0))
	var points := PackedVector2Array()
	for vertex in vertices:
		var delta := Vector2(float(vertex[0]) - float(at[0]), float(vertex[1]) - float(at[2]))
		points.append(Vector2(delta.x * cos(yaw) - delta.y * sin(yaw), delta.x * sin(yaw) + delta.y * cos(yaw)))
	var indices := Geometry2D.triangulate_polygon(points)
	for i in range(0, indices.size(), 3):
		var a := Vector3(points[indices[i]].x, -0.025, points[indices[i]].y)
		var b := Vector3(points[indices[i + 1]].x, -0.025, points[indices[i + 1]].y)
		var c := Vector3(points[indices[i + 2]].x, -0.025, points[indices[i + 2]].y)
		# Geometry2D winding is counterclockwise in x/z; this order faces upward.
		kit.triangle(a, b, c, "stone")
		kit.solid_convex(PackedVector3Array([a, b, c, a - Vector3.UP * depth, b - Vector3.UP * depth, c - Vector3.UP * depth]))
	for i in points.size():
		var j := (i + 1) % points.size()
		var a := Vector3(points[i].x, -0.025, points[i].y)
		var b := Vector3(points[j].x, -0.025, points[j].y)
		kit.triangle(a, a - Vector3.UP * depth, b, "stone")
		kit.triangle(b, a - Vector3.UP * depth, b - Vector3.UP * depth, "stone")

