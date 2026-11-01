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
	var shrubs := 0
	var mature := true
	for plants in vegetation._cells.values():
		for plant in plants:
			if str(plant.kind).begins_with("bush"):
				shrubs += 1
				mature = mature and float(plant.height) >= 1.25 and float(plant.height) <= 1.85
	var original = JSON.parse_string(FileAccess.get_file_as_string(vegetation.DATA_PATH))
	var source_shrubs := 0
	for plant in original.plants:
		source_shrubs += int(str(plant.kind).begins_with("bush"))
	check(shrubs == source_shrubs and mature, "all original shrubs become mature masses at their existing anchors")
	var bounded := true
	for key in vegetation._template_vertices:
		if not str(key).begins_with("bush"):
			continue
		for vertex in vegetation._template_vertices[key]:
			bounded = bounded and Vector2(vertex.x, vertex.z).length() <= 1.001 and vertex.y >= -0.001 and vertex.y <= 1.001
	check(bounded, "shrub templates stay inside audited footprints and start at ground")
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

func _has_color(mesh: ArrayMesh, wanted: Color) -> bool:
	var colors: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	for color in colors:
		if absf(color.r - wanted.r) < 0.01 and absf(color.g - wanted.g) < 0.01 and absf(color.b - wanted.b) < 0.01:
			return true
	return false
