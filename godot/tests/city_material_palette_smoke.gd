extends SceneTree
## Full-detail geometry/material/physics preservation through palette batching.
const Optimizer := preload("res://scripts/city/city_render_optimizer.gd")
const Surface := preload("res://assets/materials/city_surface.gdshader")
var passes := 0
var fails := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	passes += int(ok)
	fails += int(not ok)
	print("[material_palette] %s %s" % ["PASS" if ok else "FAIL", label])

func paint(color: Color, roughness: float, kind: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = Surface
	material.set_shader_parameter("albedo", color)
	material.set_shader_parameter("roughness", roughness)
	material.set_shader_parameter("surface_kind", kind)
	return material

func triangle(x: float, indexed: bool = true) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(x, 0, 0), Vector3(x + 1, 0, 0), Vector3(x, 1, 0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.UP])
	if indexed:
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	return arrays

func _run() -> void:
	var names: Array[String] = []
	for uniform in Surface.get_shader_uniform_list():
		names.append(str(uniform.name))
	check("use_vertex_palette" in names, "city surface explicitly supports the opt-in CUSTOM0 palette contract")
	if fails > 0:
		quit(1)
		return
	var city := Node3D.new()
	root.add_child(city)
	var optimizer := Optimizer.new()
	city.add_child(optimizer)
	optimizer.city = city
	optimizer.level = city
	optimizer.batch_root = Node3D.new()
	city.add_child(optimizer.batch_root)
	var red := paint(Color("9a5a44"), 0.713, 1)
	var blue := paint(Color("719bac"), 0.927, 1)
	var concrete := paint(Color("9a968c"), 0.84, 2)
	var priority := paint(Color.WHITE, 0.713, 1)
	priority.render_priority = 1
	var glass := StandardMaterial3D.new()
	glass.resource_name = "untouched_glass"
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.2, 0.3, 0.4, 0.6)
	var multipass := paint(Color.RED, 0.6, 1)
	multipass.next_pass = StandardMaterial3D.new()
	var materials: Array[Material] = [red, blue, concrete, priority, glass, multipass, red]
	var mesh := ArrayMesh.new()
	for i in materials.size():
		var arrays := triangle(float(i) * 2.0, i != 1)
		var flags := 0
		if i == 6:
			arrays[Mesh.ARRAY_CUSTOM0] = PackedFloat32Array([1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4])
			flags = Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		# Exercise effective overrides rather than accidentally reading base paint.
		mesh.surface_set_material(i, StandardMaterial3D.new())
	var instance := MeshInstance3D.new()
	instance.name = "PaletteFixture"
	instance.mesh = mesh
	instance.position = Vector3(3, 4, 5)
	optimizer.batch_root.add_child(instance)
	for i in materials.size():
		instance.set_surface_override_material(i, materials[i])
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	city.add_child(body)
	var body_rid := body.get_rid()
	optimizer._stats = {"building_surfaces": materials.size(), "building_triangles": materials.size(), "source_surfaces": materials.size()}
	var bounds := mesh.get_aabb()
	var report: Dictionary = optimizer.consolidate_material_palette(false)
	check(bool(report.enabled) and int(report.surfaces_before) == 7 and int(report.surfaces_after) == 6,
		"only the two compatible palette finishes merge")
	check(int(report.palette_materials) == 3, "surface kind and rendering priority remain separate material groups")
	var result := instance.mesh as ArrayMesh
	check(optimizer._triangle_count(result) == 7 and result.get_aabb() == bounds,
		"all original triangles and chunk bounds survive consolidation")
	check(body.get_rid() == body_rid and shape.shape is BoxShape3D and instance.position == Vector3(3, 4, 5),
		"collision registration and chunk transform stay unchanged")
	var merged := result.surface_get_arrays(0)
	var vertices: PackedVector3Array = merged[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = merged[Mesh.ARRAY_INDEX]
	var palette: PackedFloat32Array = merged[Mesh.ARRAY_CUSTOM0]
	check(vertices.size() == 6 and indices == PackedInt32Array([0, 1, 2, 3, 4, 5]),
		"indexed and unindexed source triangles retain order with adjusted indices")
	var colors_ok := palette.size() == 24
	for i in 6:
		var expected: Color = red.get_shader_parameter("albedo") if i < 3 else blue.get_shader_parameter("albedo")
		var roughness: float = 0.713 if i < 3 else 0.927
		colors_ok = colors_ok and absf(palette[i * 4] - expected.r) < 0.000001
		colors_ok = colors_ok and absf(palette[i * 4 + 1] - expected.g) < 0.000001
		colors_ok = colors_ok and absf(palette[i * 4 + 2] - expected.b) < 0.000001
		colors_ok = colors_ok and absf(palette[i * 4 + 3] - roughness) < 0.000001
	check(colors_ok, "each source retains full-precision sRGB color and calibrated roughness")
	check(merged[Mesh.ARRAY_COLOR] == null or merged[Mesh.ARRAY_COLOR].is_empty(),
		"temporary LOD seam colors do not add or overwrite stored COLOR data")
	check(result.surface_get_material(3) == glass and result.surface_get_material(4) == multipass,
		"transparent glass and multipass materials retain their exact resources")
	check(result.surface_get_arrays(5)[Mesh.ARRAY_CUSTOM0] == mesh.surface_get_arrays(6)[Mesh.ARRAY_CUSTOM0],
		"pre-existing CUSTOM0 geometry is passed through unchanged")
	var overrides_clear := true
	for i in result.get_surface_count():
		overrides_clear = overrides_clear and instance.get_surface_override_material(i) == null
	check(overrides_clear, "old surface override slots cannot paint a different consolidated surface")
	check(result.shadow_mesh != null and result.shadow_mesh.get_surface_count() == result.get_surface_count(),
		"shadow mesh retains the consolidated surface slot mapping")
	check(optimizer._palette_descriptor(red, mesh.surface_get_format(0)).key != optimizer._palette_descriptor(concrete, mesh.surface_get_format(0)).key,
		"non-palette shader uniforms participate in the grouping key")
	var changed := red.duplicate() as ShaderMaterial
	changed.set_shader_parameter("roughness", 0.456)
	check(optimizer._material_fingerprint(red) != optimizer._material_fingerprint(changed),
		"persisted cache identity changes with calibrated roughness")
	var unset_defaults := paint(Color("9a5a44"), 0.713, 1)
	unset_defaults.set_shader_parameter("use_vertex_palette", null)
	var unset_fingerprint := optimizer._material_fingerprint(unset_defaults)
	unset_defaults.get_property_list()
	check(optimizer._material_fingerprint(unset_defaults) == unset_fingerprint,
		"property enumeration during duplicate/save cannot change effective shader cache identity")
	unset_defaults.set_shader_parameter("use_vertex_palette", false)
	var queried_default = RenderingServer.shader_get_parameter_default(Surface.get_rid(), "use_vertex_palette")
	if DisplayServer.get_name() == "headless" and queried_default == null:
		print("[material_palette] SKIP default equivalence: headless dummy renderer exposes no shader uniform defaults; covered by graphical fixture")
	else:
		check(optimizer._material_fingerprint(unset_defaults) == unset_fingerprint,
			"unset and explicit default uniforms share one stable fingerprint")
	check(":true:" in optimizer.palette_cache_signature(), "stream cache records the applied palette schema")
	optimizer.rebind_shared_materials(instance)
	var reload := MeshInstance3D.new()
	reload.mesh = result.duplicate(true) as ArrayMesh
	optimizer.batch_root.add_child(reload)
	optimizer.rebind_shared_materials(reload)
	var materials_shared := true
	for i in result.get_surface_count():
		materials_shared = materials_shared and reload.get_active_material(i) == instance.get_active_material(i)
	check(materials_shared, "streamed copies rebind palette, glass and other materials to canonical resources")
	var distinct := MeshInstance3D.new()
	var distinct_mesh := ArrayMesh.new()
	distinct_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, triangle(0))
	var different_glass := glass.duplicate() as StandardMaterial3D
	different_glass.roughness = 0.123
	distinct_mesh.surface_set_material(0, different_glass)
	distinct.mesh = distinct_mesh
	optimizer.batch_root.add_child(distinct)
	optimizer.rebind_shared_materials(distinct)
	check(distinct.get_active_material(0) != glass, "identical resource names cannot merge materials with different parameters")
	optimizer.quality = "low"
	optimizer.apply_chunk_quality(instance)
	optimizer.apply_chunk_quality(reload)
	check(is_equal_approx(instance.lod_bias, 0.7) and reload.lod_bias == instance.lod_bias
		and reload.visibility_range_end == instance.visibility_range_end,
		"initial and reloaded chunks receive one authoritative quality policy")
	var kit := preload("res://scripts/city/city_civic_mesh_kit.gd").new("CivicPaletteFixture")
	kit.material("red_trim", Color("ad4732"), 6, 0.73)
	kit.material("blue_trim", Color("427a9e"), 6, 0.91)
	kit.material("brick", Color("784a39"), 1, 0.82)
	kit.box(Vector3.ZERO, Vector3.ONE, "red_trim")
	kit.box(Vector3(2, 0, 0), Vector3.ONE, "blue_trim")
	kit.box(Vector3(4, 0, 0), Vector3.ONE, "brick")
	kit.solid_box(Vector3(2, 0, 0), Vector3(5, 1, 1))
	var authored_body: StaticBody3D = kit.body
	var authored_shape: Shape3D = authored_body.get_child(0).shape
	var sign := kit.label("CORNER STORE", Vector3(0, 2, 0))
	var authored: Node3D = kit.finish()
	root.add_child(authored)
	var authored_mesh: ArrayMesh = authored.get_node("BatchedArchitecture").mesh
	check(authored.get_meta("civic_surfaces_before") == 3 and authored_mesh.get_surface_count() == 2,
		"civic kit merges compatible trim finishes while keeping brick separate")
	check(optimizer._triangle_count(authored_mesh) == 36,
		"civic palette retains all full-detail triangles")
	check(kit.body == authored_body and authored_body.get_child(0).shape == authored_shape and sign.get_parent() == authored,
		"civic batching preserves physical shapes and readable signs")
	var civic_colors := {}
	for surface in authored_mesh.get_surface_count():
		var data: PackedFloat32Array = authored_mesh.surface_get_arrays(surface)[Mesh.ARRAY_CUSTOM0]
		for offset in range(0, data.size(), 4):
			civic_colors[Color(data[offset], data[offset+1], data[offset+2]).to_html(false)] = data[offset+3]
	check(civic_colors.size() == 3 and absf(float(civic_colors.get("ad4732", 0)) - .73) < .00001 and absf(float(civic_colors.get("427a9e", 0)) - .91) < .00001,
		"civic color and roughness survive shared material surfaces")
	print("[material_palette] %d passed, %d failed" % [passes, fails])
	quit(0 if fails == 0 else 1)
