extends RefCounted
## Static walk-in shell. No whole-building hull: wall, floor, counter and ramp
## shapes leave a real two-metre doorway and a continuous walkable interior.
## A kind closed by city_play_mode.gd keeps the whole shell, interior and
## approach, but its doorway is sealed by a solid locked roll-down shutter with
## a CLOSED notice, and the counter prompt is omitted.
const PlayMode := preload("res://scripts/city/city_play_mode.gd")
const Kit := preload("res://scripts/city/city_civic_mesh_kit.gd")
const Foundations := preload("res://scripts/city/city_civic_businesses.gd")
const Bindings := preload("res://scripts/city/city_input_bindings.gd")

## A service window on an existing civic storefront. It occupies the display
## bay beside the central door, never adds an invisible whole-building hull,
## and keeps its shallow shelf inside the established frontage clearance.
static func service_window(entry: Dictionary) -> Node3D:
	var k := Kit.new(str(entry.id) + "ServiceWindow")
	k.material("trim", Color("395f58"), 4)
	k.material("wood", Color("a67b4e"), 0)
	k.material("glass", Color("253c3c"), 0)
	var front := float(entry.depth) * 0.5
	var x := float(entry.width) * 0.25 + 0.35
	k.box(Vector3(x, 1.55, front + 0.12), Vector3(1.9, 1.32, 0.12), "trim")
	k.box(Vector3(x, 1.56, front + 0.20), Vector3(1.65, 1.06, 0.08), "glass")
	_solid(k, Vector3(x, 1.0, front + 0.27), Vector3(2.02, 0.12, 0.42), "wood")
	var prompt := k.label("PANTRY COUNTER · %s" % Bindings.label("city_interact"), Vector3(x, 2.12, front + 0.26), 27, 0.005)
	prompt.name = "ShopInteractionLabel"
	prompt.set_meta("shop_prompt_format", "PANTRY COUNTER · %s")
	k.label("BIKE COLORS · BANDANAS\nSNACKS · WATER", Vector3(x, 1.56, front + 0.255), 25, 0.005)
	var model := k.finish()
	model.position = point(entry.position)
	model.rotation.y = float(entry.yaw)
	model.set_meta("service_window", true)
	# This customer point sits on the existing civic foundation apron, whose
	# top is -0.025 (not on the central doorstep's lower entry_rise landing).
	model.set_meta("counter_local", Vector3(x, -0.025, front + 1.1))
	_set_ranges(model)
	return model

static func is_closed(entry: Dictionary) -> bool:
	return not PlayMode.shop_kind_open(str(entry.get("kind", "")))

static func build(entry: Dictionary) -> Node3D:
	var k := Kit.new(str(entry.id))
	var weed: bool = str(entry.kind) == "weed"
	var closed := is_closed(entry)
	var w := float(entry.width)
	var d := float(entry.depth)
	var front := d * 0.5
	var wall := 0.22
	var door := float(entry.door_width)
	var brick := Color("805c47") if str(entry.side) == "west" else Color("756352")
	k.material("brick", brick, 1)
	k.material("stone", Color("a79d89"), 2)
	k.material("inside", Color("c4baa1"), 0)
	k.material("trim", Color("314d42") if weed else Color("36444c"), 6)
	k.material("wood", Color("795b3c"), 0)
	k.material("stock", Color("a7be7b") if weed else Color("333a3d"), 0)
	_foundation_with_entry_notch(k, entry, w, d)
	_solid(k, Vector3(0, -0.07, 0), Vector3(w, 0.14, d), "stone")
	for side in [-1.0, 1.0]:
		_solid(k, Vector3(side * (w * 0.5 - wall * 0.5), 1.65, 0), Vector3(wall, 3.3, d), "brick")
		# Light interior lining is geometry, not a floating external decal.
		k.box(Vector3(side * (w * 0.5 - wall - 0.012), 1.55, 0), Vector3(0.025, 3.1, d - wall), "inside")
	_solid(k, Vector3(0, 1.65, -front + wall * 0.5), Vector3(w, 3.3, wall), "brick")
	k.box(Vector3(0, 1.55, -front + wall + 0.012), Vector3(w - wall, 3.1, 0.025), "inside")
	_solid(k, Vector3(0, 3.37, 0), Vector3(w + 0.1, 0.22, d + 0.1), "stone")
	# Two front wall bays and a lintel; the centre remains completely open.
	var bay := (w - door) * 0.5
	for side in [-1.0, 1.0]:
		var x: float = float(side) * (door * 0.5 + bay * 0.5)
		_solid(k, Vector3(x, 1.65, front - wall * 0.5), Vector3(bay, 3.3, wall), "brick")
		k.box(Vector3(x, 1.35, front + 0.02), Vector3(maxf(0.6, bay - 0.28), 1.4, 0.045), "trim")
		k.box(Vector3(x, 1.35, front + 0.05), Vector3(maxf(0.4, bay - 0.5), 1.1, 0.025), "wood")
	_solid(k, Vector3(0, 2.95, front - wall * 0.5), Vector3(door, 0.7, wall), "brick")
	for x in [-door * 0.5, door * 0.5]:
		k.box(Vector3(x, 1.3, front + 0.01), Vector3(0.07, 2.6, 0.12), "trim")
	k.box(Vector3(0, 2.63, front + 0.02), Vector3(door + 0.14, 0.08, 0.14), "trim")
	k.box(Vector3(0, 3.03, front + 0.15), Vector3(w - 0.3, 0.54, 0.24), "trim")
	var title := str(entry.label).to_upper()
	k.label(title, Vector3(0, 3.04, front + 0.28), 38, minf(0.01, (w - 0.6) / (title.length() * 23.0)))
	if closed:
		_shutter(k, front, door)
	else:
		k.label("OPEN · WALK IN", Vector3(0, 2.43, front + 0.07), 28, 0.007)
	var counter_z := -d * 0.22
	_solid(k, Vector3(0, 0.48, counter_z), Vector3(w - 1.1, 0.96, 0.7), "wood")
	k.box(Vector3(0, 1.0, counter_z), Vector3(w - 1.0, 0.12, 0.83), "trim")
	if not closed:
		var prompt := k.label("COUNTER · %s TO SHOP" % Bindings.label("city_interact"), Vector3(0, 1.48, counter_z + 0.37), 30, 0.008)
		prompt.name = "ShopInteractionLabel"
		prompt.set_meta("shop_prompt_format", "COUNTER · %s TO SHOP")
	# Shelves run along the side walls, leaving a >3m aisle even in narrow shops.
	for side in [-1.0, 1.0]:
		var x: float = float(side) * (w * 0.5 - 0.52)
		for z in [-front + 1.0, -d * 0.04, d * 0.22]:
			_solid(k, Vector3(x, 0.45, z), Vector3(0.56, 0.9, 1.5), "wood")
			for y in [1.0, 1.65, 2.3]:
				k.box(Vector3(x, y, z), Vector3(0.64, 0.075, 1.6), "trim")
				for i in 3:
					var item_z: float = z + (float(i) - 1.0) * 0.44
					if weed:
						# Sealed fictional stock; no cultivation or usage instructions.
						k.cylinder(Vector3(x, y + 0.16, item_z), 0.09, 0.23, "stock", 8)
						k.cylinder(Vector3(x, y + 0.29, item_z), 0.095, 0.04, "trim", 8)
					else:
						k.box(Vector3(x, y + 0.16, item_z), Vector3(0.33, 0.23, 0.28), "stock")
						k.box(Vector3(x - side * 0.18, y + 0.16, item_z), Vector3(0.02, 0.08, 0.19), "inside")
	# Simple locked display silhouettes identify the gun shop without new models.
	if not weed:
		for index in 3:
			var x := (float(index) - 1.0) * (w - 1.4) / 3.0
			var z := -front + 0.29
			k.box(Vector3(x, 1.9, z), Vector3(0.72, 1.0, 0.09), "wood")
			k.box(Vector3(x, 1.99, z + 0.07), Vector3(0.5, 0.09, 0.09), "stock")
			k.box(Vector3(x - 0.13, 1.87, z + 0.07), Vector3(0.09, 0.22, 0.09), "stock")
			k.label(["PISTOL", "UZI", "AK47"][index], Vector3(x, 1.52, z + 0.08), 25, 0.006)
	else:
		k.label("SEALED CANNABIS\nFICTIONAL INVENTORY", Vector3(0, 2.0, -front + 0.29), 30, 0.009)
	var model := k.finish()
	model.set_meta("walk_in_shop", true)
	model.set_meta("closed", closed)
	model.set_meta("door_width", door)
	model.set_meta("counter_local", Vector3(0, 0, counter_z + 1.25))
	model.set_meta("interior_width", w - wall * 2.0)
	model.set_meta("interior_depth", d - wall * 2.0)
	model.position = point(entry.position)
	model.rotation.y = float(entry.yaw)
	_set_ranges(model)
	return model

static func approach(entry: Dictionary) -> Node3D:
	var k := Kit.new(str(entry.id) + "Approach")
	k.material("walk", Color("aaa18d"), 2)
	var a := point(entry.approach_start)
	var b := point(entry.entry_world)
	var right := Vector3(b.z - a.z, 0, a.x - b.x).normalized()
	var points := [a - right, a + right, b + right, b - right]
	for indices in [[0, 1, 2], [0, 2, 3]]:
		var first: Vector3 = points[indices[0]]
		var second: Vector3 = points[indices[1]]
		var third: Vector3 = points[indices[2]]
		if (third - first).cross(second - first).y < 0.0:
			var swap := second
			second = third
			third = swap
		k.triangle(first, second, third, "walk")
		k.solid_convex(PackedVector3Array([first, second, third, first - Vector3.UP * 0.16, second - Vector3.UP * 0.16, third - Vector3.UP * 0.16]))
	var result := k.finish()
	_set_ranges(result)
	return result

static func _foundation_with_entry_notch(k: RefCounted, entry: Dictionary, width: float, depth: float) -> void:
	# The exported house footprint can project farther toward the street than
	# our inset shop. Its flat foundation must not rise through the entry ramp.
	# Clip only that ramp corridor; the ramp remains solid physical support and
	# the shop floor covers the small overlap at its inner end.
	var polygon := PackedVector2Array()
	for point_value in entry.foundation_polygon:
		polygon.append(Vector2(float(point_value[0]), float(point_value[1])))
	var start := Vector2(float(entry.approach_start[0]), float(entry.approach_start[2]))
	var finish := Vector2(float(entry.entry_world[0]), float(entry.entry_world[2]))
	var direction := (finish - start).normalized()
	var right := Vector2(-direction.y, direction.x) * 1.06
	start -= direction * 0.2
	finish += direction * 0.3
	var corridor := PackedVector2Array([start - right, start + right, finish + right, finish - right])
	for remainder in Geometry2D.clip_polygons(polygon, corridor):
		var piece: Dictionary = entry.duplicate()
		var points: Array = []
		for vertex in remainder:
			points.append([vertex.x, vertex.y])
		piece.foundation_polygon = points
		Foundations._foundation(k, piece, width, depth, float(entry.foundation_depth))

## Locked roll-down shutter filling the 2 m x 2.6 m doorway under the lintel.
## It is real layer-2 architecture (as solid as the walls), so nobody walks in
## and checkpoint line-of-sight treats the interior as sealed.
static func _shutter(k: RefCounted, front: float, door: float) -> void:
	k.material("shutter", Color("7e8689"), 6)
	_solid(k, Vector3(0, 1.3, front - 0.05), Vector3(door + 0.04, 2.6, 0.06), "shutter")
	for i in 12:
		k.box(Vector3(0, 0.12 + float(i) * 0.2, front - 0.015), Vector3(door - 0.04, 0.025, 0.02), "trim")
	k.box(Vector3(0, 2.5, front + 0.04), Vector3(door - 0.02, 0.2, 0.1), "trim")
	k.box(Vector3(0, 0.06, front - 0.01), Vector3(door, 0.08, 0.04), "trim")
	k.box(Vector3(0.0, 0.13, front + 0.025), Vector3(0.09, 0.11, 0.04), "stock")
	k.label("CLOSED", Vector3(0, 1.72, front + 0.012), 46, 0.010)
	k.label("UNTIL FURTHER NOTICE", Vector3(0, 1.38, front + 0.012), 24, 0.005)

static func _solid(k: RefCounted, at: Vector3, size: Vector3, finish: String) -> void:
	k.box(at, size, finish)
	k.solid_box(at, size)

static func point(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func _set_ranges(node: Node) -> void:
	if node is MeshInstance3D:
		node.visibility_range_end = 210.0
	for child in node.get_children():
		_set_ranges(child)
