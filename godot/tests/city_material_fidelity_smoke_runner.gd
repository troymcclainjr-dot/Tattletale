extends Node
## Finish classification, shared reuse, roughness bounds, the legacy profile
## switch and isolation from imported ClayLib materials. Shaders do not execute
## headless: these are resource and uniform contracts, not visual evidence.
const Weathering := preload("res://scripts/city/city_weathering.gd")
const Windows := preload("res://scripts/city/city_windows.gd")
const Surface := preload("res://assets/materials/city_surface.gdshader")
const Glass := preload("res://assets/materials/city_glass.gdshader")
const RoadWear := preload("res://assets/materials/city_road_wear.gdshader")
const Clay := preload("res://assets/materials/clay.gdshader")
const CITY_PATH := "res://assets/models/city/pen_lucy.glb"
## Pen Lucy finishes from blender/city/process.py MATS and kits.py KIT_MATS with
## the kind each must receive; 0 keeps the imported material untouched.
const PALETTE := {
	"clay_3a3a40_r95": 3, "clay_a8a49a_r86": 2, "clay_c8c4b8_r86": 2, "clay_8a8a90_r90": 2,
	"clay_6a8a3a_r95": 5, "clay_6e5a3c_r95": 5, "clay_7d7a70_r95": 5, "clay_9a5a44_r90": 1,
	"clay_8a4a3a_r90": 1, "clay_a8644a_r90": 1, "clay_6e3a30_r90": 1, "clay_9a968c_r92": 2,
	"clay_b4a68a_r92": 2, "clay_d8d0c0_r86": 2, "clay_eeeae0_r60": 2, "clay_c8b89a_r86": 4,
	"clay_e6e2d6_r86": 4, "clay_a8aca8_r86": 4, "clay_d8c890_r86": 4, "clay_9aa88a_r86": 4,
	"clay_b0a890_r90": 4, "clay_9a9aa0_r90": 4, "clay_3f6a4a_r85": 4, "clay_9a3a32_r85": 4,
	"clay_6a4a32_r85": 4, "clay_d8d8d0_r85": 4, "clay_1a2a5a_r80": 4, "clay_8a2420_r80": 4,
	"clay_2f4a34_r80": 4, "clay_f4f0e6_r80": 6, "clay_e2d4b4_r80": 6, "clay_3f5a44_r80": 6,
	"clay_5a3a28_r80": 6, "clay_8a2a24_r80": 6, "clay_5a5a62_r90": 0, "clay_6a5846_r86": 0,
	"clay_a8a8ae_r70": 0, "clay_3e3e44_r95": 0, "gloss_8a2420_r45": 0, "gloss_6a4426_r50": 0,
	"metal_c8a040_r35": 0,
}
## Plausible authored roughness of dry, aged exterior finishes by kind.
const KIND_ROUGHNESS := {1: Vector2(0.80, 1.0), 2: Vector2(0.55, 1.0), 3: Vector2(0.85, 1.0),
	4: Vector2(0.70, 1.0), 5: Vector2(0.90, 1.0), 6: Vector2(0.70, 1.0)}
var passes := 0
var fails := 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passes += 1
	else:
		fails += 1
	print("[material_fidelity] %s %s" % ["PASS" if ok else "FAIL", label])

func _run() -> void:
	var shaders: Array[Shader] = [Surface, Glass, RoadWear]
	var originals: Array[String] = []
	for shader in shaders:
		originals.append(shader.code)
	_contracts(shaders)
	_classification()
	_synthetic_city()
	_imported_city()
	_legacy_profile(shaders, originals)
	print("[material_fidelity] %d passed, %d failed" % [passes, fails])
	get_tree().quit(0 if fails == 0 else 1)

func _uniforms(shader: Shader) -> Dictionary:
	var result := {}
	for uniform in shader.get_shader_uniform_list():
		result[str(uniform.name)] = int(uniform.type)
	return result

func _authored_roughness(finish: String) -> float:
	return float(finish.split("_")[2].substr(1)) / 100.0

func _contracts(shaders: Array[Shader]) -> void:
	var surface := _uniforms(Surface)
	check(int(surface.get("albedo", -1)) == TYPE_COLOR and int(surface.get("roughness", -1)) == TYPE_FLOAT
		and int(surface.get("surface_kind", -1)) == TYPE_INT and int(surface.get("use_vertex_palette", -1)) == TYPE_BOOL,
		"city surface exposes finish uniforms and the optimizer's opt-in CUSTOM0 palette switch")
	check(Weathering.finish_profile() == "calibrated", "calibrated finishes are the default profile")
	var swaps := true
	for shader in shaders:
		var legacy := Weathering.legacy_code(shader.code)
		var variant := Shader.new()
		variant.code = legacy
		swaps = swaps and shader.code.count(Weathering.CALIBRATED_DEFINE) == 1
		swaps = swaps and legacy.count(Weathering.LEGACY_DEFINE) == 1 and not legacy.contains(Weathering.CALIBRATED_DEFINE)
		swaps = swaps and _uniforms(variant) == _uniforms(shader)
	check(swaps, "each city shader changes profile through one define with identical uniforms")

func _classification() -> void:
	var wrong: Array[String] = []
	var bounded := true
	for finish in PALETTE:
		var kind: int = PALETTE[finish]
		if Weathering.classify(finish) != kind:
			wrong.append(finish)
		if kind > 0:
			var limits: Vector2 = KIND_ROUGHNESS[kind]
			var authored := _authored_roughness(finish)
			bounded = bounded and authored >= limits.x and authored <= limits.y
	check(wrong.is_empty(), "every Pen Lucy palette finish keeps its weathering class %s" % [wrong])
	check(bounded, "authored roughness of each weathered palette finish lies in its kind's dry-exterior range")

func _imported(finish: String) -> ShaderMaterial:
	# Same shape as the import hook's shared, convention-named clay material.
	var material := ShaderMaterial.new()
	material.shader = Clay
	material.resource_name = finish
	material.set_shader_parameter("albedo", Color.html("#" + finish.split("_")[1]))
	material.set_shader_parameter("roughness", _authored_roughness(finish))
	return material

func _triangles(materials: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for i in materials.size():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(i, 0, 0), Vector3(i + 1, 0, 0), Vector3(i, 1, 0)])
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(i, materials[i])
	return mesh

func _snapshot(city: Node) -> Array:
	# Base mesh slots and the parameters of the shared imported materials.
	var result := []
	for node in city.find_children("*", "MeshInstance3D", true, false):
		if node.mesh == null:
			continue
		for surface in node.mesh.get_surface_count():
			var material: Material = node.mesh.surface_get_material(surface)
			var entry := [node.get_instance_id(), surface, material.get_instance_id() if material else 0]
			if material is ShaderMaterial:
				entry.append_array([material.shader, material.get_shader_parameter("albedo"), material.get_shader_parameter("roughness")])
			result.append(entry)
	return result

func _synthetic_city() -> void:
	var city := Node3D.new()
	add_child(city)
	var imported := {}
	for finish in PALETTE:
		imported[finish] = _imported(finish)
	imported[Windows.GLASS_NAME] = _imported(Windows.GLASS_NAME)
	var index := 0
	for finish in imported:
		var node := MeshInstance3D.new()
		node.name = "Row_%d" % index
		node.mesh = _triangles([imported[finish]])
		city.add_child(node)
		index += 1
	# A second building reuses imported brick, asphalt and glass in one mesh.
	var reuse := MeshInstance3D.new()
	reuse.name = "Bldg_reuse"
	reuse.mesh = _triangles([imported["clay_9a5a44_r90"], imported["clay_3a3a40_r95"], imported[Windows.GLASS_NAME]])
	city.add_child(reuse)
	var trees := MeshInstance3D.new()
	trees.name = "Trees"
	trees.mesh = _triangles([imported["clay_9a5a44_r90"]])
	city.add_child(trees)
	var before := _snapshot(city)
	var surface_code := Surface.code
	var report: Dictionary = Weathering.apply_materials(city)
	var by_finish := {}
	var glass := {}
	var classified := true
	var reused := true
	var bounded := true
	var glass_ok := true
	var weathered := 0
	for node in city.find_children("*", "MeshInstance3D", true, false):
		for surface in node.mesh.get_surface_count():
			var base: Material = node.mesh.surface_get_material(surface)
			var override: Material = node.get_surface_override_material(surface)
			var finish := base.resource_name
			if str(node.name).begins_with("Trees"):
				classified = classified and override == null
				continue
			if finish == Windows.GLASS_NAME:
				glass_ok = glass_ok and override is ShaderMaterial and override.shader == Glass and override != base
				glass[override] = true
				continue
			var kind: int = PALETTE[finish]
			if kind == 0:
				classified = classified and override == null
				continue
			weathered += 1
			classified = classified and (override is ShaderMaterial and override.shader == Surface
				and override != base and override.resource_name == finish
				and int(override.get_shader_parameter("surface_kind")) == kind
				and override.get_shader_parameter("albedo") == Color.html("#" + finish.split("_")[1])
				and override.get_shader_parameter("use_vertex_palette") != true)
			if not override is ShaderMaterial:
				continue
			var rough := float(override.get_shader_parameter("roughness"))
			var limits: Vector2 = KIND_ROUGHNESS[kind]
			bounded = bounded and is_equal_approx(rough, _authored_roughness(finish)) and rough >= limits.x and rough <= limits.y
			if by_finish.has(finish):
				reused = reused and by_finish[finish] == override
			else:
				by_finish[finish] = override
	var unique := {}
	for finish in by_finish:
		unique[by_finish[finish]] = true
	check(classified, "palette names get their finish kind; roofs, gloss, metal and trees keep imported materials")
	check(reused and unique.size() == by_finish.size(), "one shared override per finish name, distinct between finishes")
	check(bounded, "weathered roughness equals the authored value and stays inside its kind's range")
	check(int(report.weathered_surfaces) == weathered and int(report.shared_finishes) == by_finish.size(),
		"report counts match %d weathered surfaces across %d shared finishes" % [weathered, by_finish.size()])
	check(glass_ok and glass.size() == 1 and int(report.rough_glass_surfaces) == 2, "both panes share one city glass material")
	check(str(report.get("finish_profile", "")) == "calibrated", "report names the running finish profile")
	check(_snapshot(city) == before and Surface.code == surface_code,
		"imported shared materials, mesh slots and shader source are never mutated")
	city.free()

func _imported_city() -> void:
	if not ResourceLoader.exists(CITY_PATH):
		print("[material_fidelity] SKIP imported city: model is not imported in this checkout")
		return
	var scene = ResourceLoader.load(CITY_PATH, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if not scene is PackedScene:
		check(false, "imported Pen Lucy model loads")
		return
	var city: Node3D = scene.instantiate()
	var before := _snapshot(city)
	var report: Dictionary = Weathering.apply_materials(city)
	var by_finish := {}
	var glass := {}
	var unknown := {}
	var reused := true
	var bounded := true
	var weathered := 0
	for node in city.find_children("*", "MeshInstance3D", true, false):
		if node.mesh == null:
			continue
		for surface in node.mesh.get_surface_count():
			var override: Material = node.get_surface_override_material(surface)
			if not override is ShaderMaterial:
				continue
			if override.shader == Glass:
				glass[override] = true
				continue
			weathered += 1
			var finish := override.resource_name
			if by_finish.has(finish):
				reused = reused and by_finish[finish] == override
			else:
				by_finish[finish] = override
			var kind := int(override.get_shader_parameter("surface_kind"))
			if PALETTE.has(finish):
				var limits: Vector2 = KIND_ROUGHNESS.get(kind, Vector2(2.0, 2.0))
				var rough := float(override.get_shader_parameter("roughness"))
				bounded = bounded and kind == int(PALETTE[finish]) and rough >= limits.x and rough <= limits.y
			else:
				unknown[finish] = kind
	check(weathered > 0 and int(report.weathered_surfaces) == weathered and int(report.shared_finishes) == by_finish.size(),
		"imported city: report matches %d weathered surfaces across %d shared finishes" % [weathered, by_finish.size()])
	check(reused, "imported city: every surface of a finish shares one override")
	check(bounded, "imported city: palette finishes keep their class and dry-exterior roughness range")
	check(glass.size() == 1 and int(report.rough_glass_surfaces) > 0, "imported city: all %d panes share one glass material" % int(report.rough_glass_surfaces))
	check(_snapshot(city) == before, "imported city: shared ClayLib materials and mesh slots are unchanged")
	if not unknown.is_empty():
		print("[material_fidelity] NOTE weathered finishes outside the Blender palette (name: kind) ", unknown)
	print("[material_fidelity] imported finish kinds ", report.get("finish_kinds", {}))
	city.free()

func _legacy_profile(shaders: Array[Shader], originals: Array[String]) -> void:
	var material := ShaderMaterial.new()
	material.shader = Surface
	material.set_shader_parameter("roughness", 0.9)
	material.set_shader_parameter("surface_kind", 1)
	var before := [_uniforms(Surface), material.get_shader_parameter("roughness"), material.get_shader_parameter("surface_kind")]
	Weathering.use_legacy_finishes()
	var switched := Weathering.finish_profile() == "legacy"
	var legacy: Array[String] = []
	for shader in shaders:
		switched = switched and shader.code.contains(Weathering.LEGACY_DEFINE) and not shader.code.contains(Weathering.CALIBRATED_DEFINE)
		legacy.append(shader.code)
	Weathering.use_legacy_finishes()
	for i in shaders.size():
		switched = switched and shaders[i].code == legacy[i]
	check(switched, "legacy profile switches all three shared shaders once, idempotently")
	check([_uniforms(Surface), material.get_shader_parameter("roughness"), material.get_shader_parameter("surface_kind")] == before,
		"legacy profile keeps uniforms and existing material values, so cached materials stay valid")
	for i in shaders.size():
		shaders[i].code = originals[i]
	check(Weathering.finish_profile() == "calibrated", "calibrated source restored after the profile check")
