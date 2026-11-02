extends SceneTree
## Headless utility topology/culling and shrub shape regression checks.
var failures := 0
class LevelFixture extends Node3D:
	var civic_district: Node

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	print("[neighborhood_utilities] %s %s" % ["PASS" if ok else "FAIL", message])
	failures += int(not ok)

func _run() -> void:
	var level := LevelFixture.new()
	root.add_child(level)
	var power := preload("res://scripts/city/city_power_grid.gd").new()
	level.add_child(power)
	power.setup(level)
	var degree: Dictionary = {}
	var valid := true
	for span in power.spans:
		valid = valid and int(span.a) >= 0 and int(span.b) >= 0 and int(span.a) < power.records.size() and int(span.b) < power.records.size()
		degree[int(span.a)] = int(degree.get(int(span.a), 0)) + 1
		degree[int(span.b)] = int(degree.get(int(span.b), 0)) + 1
	check(valid, "all wire endpoints reference retained supports")
	check(degree.size() == power.records.size(), "no isolated decorative poles remain")
	check(power.spans.size() > 110, "audited safe missing street connections are restored")
	check(power._transformer_count > 5, "transformers are distributed on connected lines")
	var terminals_correct := true
	for i in power.records.size():
		terminals_correct = terminals_correct and (bool(power.records[i].terminal) == (int(degree[i]) == 1))
	check(terminals_correct, "every dead-end has a terminating riser")
	var supported := true
	for focus in [Vector3(-200, 0, -300), Vector3(450, 0, -150), Vector3(20, 0, 250)]:
		power.set_presence(focus, 30, 70)
		for cell in power._cells.values():
			if cell.wires == null or not cell.wires.visible:
				continue
			for span in cell.spans:
				supported = supported and power._cell(power._point(power.records[int(span.a)].position)).pole_node.visible
				supported = supported and power._cell(power._point(power.records[int(span.b)].position)).pole_node.visible
	check(supported, "all visible spans retain both endpoint supports at culling boundaries")
	var vegetation := preload("res://scripts/city/city_vegetation.gd").new()
	level.add_child(vegetation)
	var city := Node3D.new()
	level.add_child(city)
	vegetation.setup(level, city)
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(vegetation.DATA_PATH))
	var growth_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(vegetation.SHRUB_GROWTH))
	check(str(growth_data.source_sha256) == FileAccess.get_sha256(vegetation.DATA_PATH), "authored mature growth is bound to the current surveyed vegetation file")
	var growth := {}
	for entry in growth_data.plants:
		growth[int(entry.index)] = entry
	var expected := {}
	var expected_counts := {"mature": 0, "pointed": 0, "authored": 0}
	var source_valid := true
	for index in original.plants.size():
		var source: Dictionary = original.plants[index]
		if not str(source.kind).begins_with("bush"):
			continue
		source_valid = source_valid and growth.has(index)
		var plant: Dictionary = source.duplicate(true)
		if growth.has(index):
			plant.height = growth[index].height
			plant.radius = growth[index].radius
		plant.group = "mature"
		var key := _shrub_key(plant)
		source_valid = source_valid and not expected.has(key)
		expected[key] = plant
		expected_counts.mature += 1
	for spec in [[vegetation.POINTED_SHRUBS, "pointed"], [vegetation.ALIVE_WORLD, "authored"]]:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(str(spec[0])))
		for source in data.get("plants", []):
			if not str(source.kind).begins_with("bush"):
				continue
			var plant: Dictionary = source.duplicate(true)
			plant.group = str(spec[1])
			source_valid = source_valid and (str(plant.kind) == "bush_spire" if plant.group == "pointed" else bool(plant.get("authored_size", false)))
			var key := _shrub_key(plant)
			source_valid = source_valid and not expected.has(key)
			expected[key] = plant
			expected_counts[plant.group] += 1
	var actual_counts := {"mature": 0, "pointed": 0, "authored": 0}
	var seen := {}
	var matched := source_valid
	var mature := true
	for plants in vegetation._cells.values():
		for plant in plants:
			if not str(plant.kind).begins_with("bush"):
				continue
			var key := _shrub_key(plant)
			if not expected.has(key) or seen.has(key):
				matched = false
				continue
			seen[key] = true
			var source: Dictionary = expected[key]
			actual_counts[source.group] += 1
			matched = matched and is_equal_approx(float(plant.height), float(source.height)) and is_equal_approx(float(plant.radius), float(source.radius))
			if source.group == "mature":
				mature = mature and float(plant.height) >= 1.25 and float(plant.height) <= 1.85
	check(matched and seen.size() == expected.size(), "all shrub groups retain exact authored anchors, yaw, radius and height without duplicates")
	check(actual_counts.mature == expected_counts.mature and actual_counts.mature > 0 and mature, "all original shrubs retain authored mature growth at surveyed anchors")
	check(actual_counts.pointed == expected_counts.pointed and actual_counts.pointed > 0 and actual_counts.authored == expected_counts.authored,
		"pointed evergreens and later authored-size shrubs retain their separate source populations")
	var bounded := true
	for key in vegetation._template_vertices:
		if not str(key).begins_with("bush"):
			continue
		# Current pointed crowns overlap the ground by .025 normalized units;
		# match the authored quality contract, without relaxing ordinary shrubs.
		var floor_y := -0.026 if str(key).begins_with("bush_spire_") else -0.001
		for vertex in vegetation._template_vertices[key]:
			bounded = bounded and vertex.is_finite() and Vector2(vertex.x, vertex.z).length() <= 1.001 and vertex.y >= floor_y and vertex.y <= 1.001
	check(bounded, "shrub footprints and tops stay bounded; only pointed crowns use authored ground overlap")
	# Load after project autoload initialization: the imported model helper also
	# references the legacy world's G singleton through its placeholder fallback.
	var fixtures = load("res://scripts/city/city_neighborhood_details.gd").new()
	level.add_child(fixtures)
	fixtures._load_utility_meshes()
	var postal: ArrayMesh = fixtures._meshes.postal_drop
	var hydrant: ArrayMesh = fixtures._meshes.hydrant
	check(_has_color(postal, Color("1f4fa8")), "extracted postal box retains its authored blue body")
	check(_has_color(hydrant, Color("c4162a")), "extracted hydrant retains its authored red enamel")
	check(_has_color(postal, Color("141414")) and _has_color(hydrant, Color("3a3a3e")), "fixture slots and metal hardware retain contrasting source colours")
	var material := postal.surface_get_material(0) as StandardMaterial3D
	check(material != null and material.vertex_color_use_as_albedo and material.vertex_color_is_srgb, "batched fixture material renders the preserved sRGB vertex colours")
	print("[neighborhood_utilities] failures=%d" % failures)
	root.remove_child(level)
	level.free()
	quit(0 if failures == 0 else 1)

func _shrub_key(plant: Dictionary) -> String:
	var at: Vector3
	if plant.position is Vector3:
		at = plant.position
	else:
		at = Vector3(float(plant.position[0]), float(plant.position[1]), float(plant.position[2]))
	return "%s:%s:%s" % [str(plant.kind), str(at), str(float(plant.yaw))]

func _has_color(mesh: ArrayMesh, wanted: Color) -> bool:
	var colors: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	for color in colors:
		if absf(color.r - wanted.r) < 0.01 and absf(color.g - wanted.g) < 0.01 and absf(color.b - wanted.b) < 0.01:
			return true
	return false
