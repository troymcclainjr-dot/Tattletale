extends RefCounted
## Pen Lucy neighborhood hospital. Ground datum Y=0; public frontage faces +Z.
## Static exterior only: geometry is batched by finish by the shared civic kit.
const Kit = preload("res://scripts/city/city_civic_mesh_kit.gd")


static func footprint() -> Vector2:
	return Vector2(55.0, 38.0)


static func build() -> Node3D:
	var k := Kit.new("PenLucyHospital")
	_palette(k)
	_main_block(k)
	_emergency_wing(k)
	_public_entry(k)
	_ambulance_entry(k)
	_roof_plant(k)
	var root: Node3D = k.finish()
	root.set_meta("civic_type", "hospital")
	root.set_meta("footprint_m", footprint())
	root.set_meta("front_local", Vector3.FORWARD * -1.0)
	root.set_meta("ground_y", 0.0)
	root.set_meta("storeys", 4)
	_marker(root, "PublicEntrance", Vector3(-9.0, 0.0, 13.15), "pedestrian", 5.0)
	_marker(root, "EmergencyEntrance", Vector3(17.0, 0.0, 3.25), "pedestrian", 4.0)
	_marker(root, "AmbulanceBay", Vector3(17.0, 0.0, 10.0), "ambulance", 12.0)
	return root


static func _palette(k) -> void:
	k.material("brick", Color("865b4b"), 1)
	k.material("brick_dark", Color("65463c"), 1)
	k.material("stone", Color("c7c3b0"), 2)
	k.material("glass", Color("3b5660"), 0, 0.29)
	k.material("metal", Color("52616a"), 6, 0.64)
	k.material("roof", Color("40484a"), 0)
	k.material("white", Color("e6e3d4"), 6)
	k.material("red", Color("963e39"), 4)
	k.material("teal", Color("31595b"), 4)
	k.material("paving", Color("aaa79b"), 2)


static func _main_block(k) -> void:
	# Four distinct floor courses and projecting masonry piers frame recessed bays.
	k.box(Vector3(-9, 8, -5), Vector3(32, 16, 24), "brick")
	k.solid_box(Vector3(-9, 8, -5), Vector3(32, 16, 24))
	k.box(Vector3(-9, 0.48, -5), Vector3(32.25, 0.96, 24.25), "stone")
	for floor_index in range(5):
		var y := 0.9 + float(floor_index) * 3.78
		var thickness := 0.18 if floor_index < 4 else 0.38
		k.box(Vector3(-9, y, -5), Vector3(32.6, thickness, 24.6), "stone")
	# Main front and rear: eight regular structural bays.
	for bay in range(8):
		var x := -23.0 + float(bay) * 4.0
		for floor_index in range(4):
			var y := 2.35 + float(floor_index) * 3.78
			if floor_index != 0 or bay < 2 or bay > 5:
				_window(k, Vector3(x, y, 7.025), 0.0, 2.85)
			_window(k, Vector3(x, y, -17.025), PI, 2.85)
	for bay in range(9):
		var x := -25.0 + float(bay) * 4.0
		k.box(Vector3(x, 8.35, 7.23), Vector3(0.44, 14.5, 0.46), "brick_dark")
		k.box(Vector3(x, 8.35, -17.23), Vector3(0.44, 14.5, 0.46), "brick_dark")
	# Six bays down the west flank; upper east bays clear the low wing.
	for bay in range(6):
		var z := -15.0 + float(bay) * 4.0
		for floor_index in range(4):
			var y := 2.35 + float(floor_index) * 3.78
			_window(k, Vector3(-25.025, y, z), -PI / 2.0, 2.85)
			if floor_index >= 2 or bay == 5:
				_window(k, Vector3(7.025, y, z), PI / 2.0, 2.85)
	for bay in range(7):
		var z := -17.0 + float(bay) * 4.0
		k.box(Vector3(-25.23, 8.35, z), Vector3(0.46, 14.5, 0.44), "brick_dark")
		k.box(Vector3(7.23, 12.0, z), Vector3(0.46, 7.2, 0.44), "brick_dark")
	_parapet(k, Vector3(-9, 16.05, -5), Vector2(32.6, 24.6), 1.1)
	# Tall entry-side identity panel also breaks the roof silhouette.
	k.box(Vector3(-22.8, 17.0, 7.05), Vector3(3.1, 3.3, 0.7), "teal")
	k.label("H", Vector3(-22.8, 17.12, 7.43), 100, 0.026)
	k.box(Vector3(-5.2, 16.58, 7.34), Vector3(23.1, 1.2, 0.15), "teal")
	k.label("PEN LUCY HOSPITAL", Vector3(-5.2, 16.6, 7.44), 64, 0.020)


static func _emergency_wing(k) -> void:
	# A lower pale wing and a short connector make an asymmetric urban complex.
	k.box(Vector3(17, 3.95, -7), Vector3(18, 7.9, 20), "stone")
	k.solid_box(Vector3(17, 3.95, -7), Vector3(18, 7.9, 20))
	k.box(Vector3(7.5, 3.9, -7), Vector3(1.2, 7.8, 19.8), "brick_dark")
	k.solid_box(Vector3(7.5, 3.9, -7), Vector3(1.2, 7.8, 19.8))
	for y in [0.55, 4.0, 7.8]:
		k.box(Vector3(17, y, -7), Vector3(18.35, 0.22, 20.35), "brick_dark")
	for bay in range(4):
		var x := 10.25 + float(bay) * 4.5
		_window(k, Vector3(x, 5.75, 3.025), 0.0, 3.1)
		for y in [2.1, 5.75]:
			_window(k, Vector3(x, y, -17.025), PI, 3.1)
	for bay in range(5):
		var z := -15.0 + float(bay) * 4.0
		for y in [2.1, 5.75]:
			_window(k, Vector3(26.025, y, z), PI / 2.0, 2.8)
	for x in [8.0, 12.5, 17.0, 21.5, 26.0]:
		k.box(Vector3(x, 5.7, 3.22), Vector3(0.35, 3.2, 0.44), "stone")
	_parapet(k, Vector3(17, 7.95, -7), Vector2(18.4, 20.4), 0.8)
	# A brick stair enclosure rises above the pale side wing.
	k.box(Vector3(22.5, 5.0, -13.5), Vector3(5.0, 10.0, 5.0), "brick")
	k.box(Vector3(22.5, 10.1, -13.5), Vector3(5.35, 0.25, 5.35), "stone")
	k.solid_box(Vector3(22.5, 9.0, -13.5), Vector3(5.0, 2.0, 5.0))


static func _public_entry(k) -> void:
	# Flush walk-in vestibule; pavement upper face and thresholds all meet Y=0.
	k.box(Vector3(-9, -0.1, 13), Vector3(18, 0.2, 12), "paving")
	k.solid_box(Vector3(-9, -0.1, 13), Vector3(18, 0.2, 12))
	k.box(Vector3(-9, 2.0, 10), Vector3(10.4, 4.0, 6.0), "glass")
	k.solid_box(Vector3(-9, 2.0, 10), Vector3(10.4, 4.0, 6.0))
	for x in [-14.2, -11.6, -9.0, -6.4, -3.8]:
		k.box(Vector3(x, 2.0, 13.08), Vector3(0.16, 4.0, 0.18), "metal")
	for x in [-14.27, -3.73]:
		k.box(Vector3(x, 2.0, 10), Vector3(0.14, 4.0, 6.0), "metal")
	k.box(Vector3(-9, 3.3, 13.13), Vector3(10.6, 0.15, 0.19), "metal")
	k.box(Vector3(-9, 0.12, 13.15), Vector3(10.6, 0.24, 0.12), "metal")
	# A pair of glass door leaves, stile/handles and a shallow protective hood.
	for x in [-10.25, -7.75]:
		k.box(Vector3(x, 1.55, 13.16), Vector3(2.35, 3.0, 0.1), "glass")
		k.box(Vector3(x + 0.8, 1.25, 13.25), Vector3(0.075, 0.55, 0.08), "white")
	k.box(Vector3(-9, 4.15, 11.5), Vector3(13.8, 0.38, 9), "stone")
	k.solid_box(Vector3(-9, 4.15, 11.5), Vector3(13.8, 0.38, 9))
	k.box(Vector3(-9, 3.87, 15.9), Vector3(13.6, 0.58, 0.16), "teal")
	k.label("MAIN ENTRANCE", Vector3(-9, 3.91, 16.01), 46, 0.018)
	for x in [-15.25, -2.75]:
		k.box(Vector3(x, 1.95, 15.15), Vector3(0.32, 3.9, 0.32), "metal")
		k.solid_box(Vector3(x, 1.95, 15.15), Vector3(0.32, 3.9, 0.32))
	# Low built-in benches flank the unobstructed central accessible approach.
	for x in [-16.4, -1.6]:
		k.box(Vector3(x, 0.26, 11.4), Vector3(1.0, 0.52, 3.4), "stone")
		k.solid_box(Vector3(x, 0.26, 11.4), Vector3(1.0, 0.52, 3.4))
		k.box(Vector3(x, 0.57, 11.4), Vector3(1.05, 0.1, 3.5), "metal")


static func _ambulance_entry(k) -> void:
	k.box(Vector3(17, -0.1, 10.75), Vector3(19, 0.2, 15.5), "paving")
	k.solid_box(Vector3(17, -0.1, 10.75), Vector3(19, 0.2, 15.5))
	# Separate covered emergency apron: over 4 m clearance and two open drive bays.
	k.box(Vector3(17, 4.65, 9.5), Vector3(18, 0.42, 13), "stone")
	k.solid_box(Vector3(17, 4.65, 9.5), Vector3(18, 0.42, 13))
	k.box(Vector3(17, 4.45, 15.95), Vector3(18, 0.62, 0.18), "red")
	k.box(Vector3(25.92, 4.45, 9.5), Vector3(0.18, 0.62, 13), "red")
	k.label("AMBULANCE", Vector3(17, 4.49, 16.06), 52, 0.018)
	k.label("EMERGENCY", Vector3(26.03, 4.49, 9.5), 50, 0.018, Color("ece5cd"), PI / 2.0)
	for x in [8.8, 25.2]:
		for z in [4.1, 14.8]:
			k.box(Vector3(x, 2.2, z), Vector3(0.3, 4.4, 0.3), "metal")
			k.solid_box(Vector3(x, 2.2, z), Vector3(0.3, 4.4, 0.3))
	# Door wall set behind the canopy: red fascia reads from the covered approach.
	k.box(Vector3(17, 1.55, 3.08), Vector3(5.2, 3.1, 0.15), "glass")
	for x in [14.4, 17.0, 19.6]:
		k.box(Vector3(x, 1.55, 3.2), Vector3(0.14, 3.1, 0.18), "metal")
	k.box(Vector3(17, 3.6, 3.2), Vector3(10.4, 0.75, 0.25), "red")
	k.label("EMERGENCY", Vector3(17, 3.65, 3.34), 54, 0.018)
	for x in [12.7, 21.3]:
		k.cylinder(Vector3(x, 0.48, 4.0), 0.12, 0.96, "white", 8)
		k.solid_box(Vector3(x, 0.48, 4.0), Vector3(0.24, 0.96, 0.24))
	# Painted berth edge guides are flat visual geometry; no vehicle or barriers.
	for x in [11.3, 16.9, 22.5]:
		k.box(Vector3(x, 0.008, 10.8), Vector3(0.1, 0.012, 7.5), "white")


static func _roof_plant(k) -> void:
	# Grouped low-detail service plant, screened toward the main street frontage.
	k.box(Vector3(-16, 17.3, -10), Vector3(7.4, 2.6, 7), "brick_dark")
	k.box(Vector3(-16, 18.68, -10), Vector3(7.8, 0.2, 7.4), "stone")
	k.solid_box(Vector3(-16, 17.4, -10), Vector3(7.8, 2.8, 7.4))
	for x in [-7.5, -2.0, 3.5]:
		k.box(Vector3(x, 16.35, -8), Vector3(4.4, 0.4, 5.8), "metal")
		k.box(Vector3(x, 17.0, -8), Vector3(3.9, 1.0, 5.2), "white")
		k.solid_box(Vector3(x, 16.95, -8), Vector3(4.4, 1.6, 5.8))
		for z in [-9.3, -6.7]:
			k.cylinder(Vector3(x, 17.56, z), 0.83, 0.12, "roof", 10)
		for y in [16.7, 16.95, 17.2]:
			k.box(Vector3(x, y, -5.36), Vector3(3.5, 0.09, 0.08), "metal")
	k.box(Vector3(-2, 17.1, -3.5), Vector3(16.0, 1.8, 0.2), "metal")
	for x in [-23.0, -20.5]:
		k.cylinder(Vector3(x, 17.5, -12.4), 0.24, 2.1, "metal", 8)
		k.cylinder(Vector3(x, 18.57, -12.4), 0.39, 0.13, "roof", 8)
	# Wing roof vents remain a single inexpensive equipment cluster.
	k.box(Vector3(14.0, 8.55, -9.0), Vector3(5.0, 1.0, 3.0), "metal")
	k.solid_box(Vector3(14.0, 8.55, -9.0), Vector3(5.0, 1.0, 3.0))
	for z in [-9.8, -8.2]:
		k.cylinder(Vector3(14, 9.1, z), 0.6, 0.15, "roof", 10)


static func _window(k, at: Vector3, yaw: float, width: float) -> void:
	# Broad dark reveal, inset blue glazing, center mullion, projecting stone sill.
	# Four boxes per bay; facade piers and floor bands supply the shared jambs/lintels.
	var basis := Basis(Vector3.UP, yaw)
	k.box(at + basis * Vector3(0, 0, 0.03), Vector3(width + 0.3, 2.55, 0.06), "roof", yaw)
	k.box(at + basis * Vector3(0, 0.05, 0.075), Vector3(width, 2.24, 0.06), "glass", yaw)
	k.box(at + basis * Vector3(0, 0.05, 0.15), Vector3(0.085, 2.27, 0.12), "metal", yaw)
	k.box(at + basis * Vector3(0, -1.24, 0.22), Vector3(width + 0.45, 0.15, 0.58), "stone", yaw)


static func _parapet(k, at: Vector3, size: Vector2, height: float) -> void:
	k.box(at, Vector3(size.x, 0.12, size.y), "roof")
	for sign_value in [-1.0, 1.0]:
		var front := at + Vector3(0, height * 0.5, sign_value * (size.y * 0.5 - 0.17))
		var side := at + Vector3(sign_value * (size.x * 0.5 - 0.17), height * 0.5, 0)
		k.box(front, Vector3(size.x, height, 0.34), "brick_dark")
		k.box(front + Vector3(0, height * 0.5, 0), Vector3(size.x + 0.14, 0.16, 0.48), "stone")
		k.box(side, Vector3(0.34, height, size.y), "brick_dark")
		k.box(side + Vector3(0, height * 0.5, 0), Vector3(0.48, 0.16, size.y + 0.14), "stone")
	# Rooftops are non-public; shell mass handles the walkable obstruction below.


static func _marker(root: Node3D, title: String, at: Vector3, use: String, width: float) -> void:
	var marker := Marker3D.new()
	marker.name = title
	marker.position = at
	marker.set_meta("use", use)
	marker.set_meta("clear_width_m", width)
	marker.set_meta("approach_local", Vector3(0, 0, 1))
	root.add_child(marker)
