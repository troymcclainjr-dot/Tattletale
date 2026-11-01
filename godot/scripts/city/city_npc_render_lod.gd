extends Node
## Render-only detail for articulated actors. Five distant surfaces retain the
## actual authored geometry/colors and original limb pivots. AI never runs here.
const People := preload("res://scripts/city/city_modular_people.gd")
const FAR_DISTANCE := 32.0
const NEAR_DISTANCE := 26.0
const SHADOW_DISTANCE := 24.0
static var enabled := true
static var _material: ShaderMaterial
var actor: Node3D
var far := false
var originals: Array[MeshInstance3D] = []
var proxies: Array[MeshInstance3D] = []
var original_layers: Array[int] = []
var original_shadows: Array[int] = []
var supported := true
var _timer := 0.0
var _animation_time := 0.0
var _shadows := true

func setup(owner_actor: Node3D) -> void:
	actor = owner_actor
	name = "RenderDetail"
	# Residents apply their initial distance fade before this deferred bake.
	# Include only their registered fading meshes, not arbitrary hidden props.
	var faded_meshes: Array = []
	if actor.has_method("set_distance_fade"):
		faded_meshes = actor._visual_meshes
	_collect(actor.puppet.g, faded_meshes)
	var pivots: Array[Node3D] = [actor.puppet.body, actor.puppet.arms[0], actor.puppet.arms[1], actor.puppet.legs[0], actor.puppet.legs[1]]
	var groups: Array[Dictionary] = []
	for pivot in pivots:
		groups.append({"vertices": PackedVector3Array(), "normals": PackedVector3Array(), "colors": PackedColorArray(), "finish": PackedVector2Array(), "indices": PackedInt32Array()})
	for source in originals:
		var group := 0
		for index in range(1, pivots.size()):
			if pivots[index] == source or pivots[index].is_ancestor_of(source):
				group = index
		var relative: Transform3D = pivots[group].global_transform.affine_inverse() * source.global_transform
		for surface in source.mesh.get_surface_count():
			if not _append_surface(groups[group], source, surface, relative):
				supported = false
	if not supported:
		set_process(false)
		return # Unknown textures/shaders keep their original appearance.
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = preload("res://assets/materials/city_npc_lod.gdshader")
	for index in groups.size():
		var data: Dictionary = groups[index]
		if data.indices.is_empty():
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = data.vertices
		arrays[Mesh.ARRAY_NORMAL] = data.normals
		arrays[Mesh.ARRAY_COLOR] = data.colors
		arrays[Mesh.ARRAY_TEX_UV] = data.finish
		arrays[Mesh.ARRAY_INDEX] = data.indices
		var importer := ImporterMesh.new()
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, _material)
		importer.generate_lods(45.0, 0.0, [])
		var visual := MeshInstance3D.new()
		visual.name = "Distant" + str(pivots[index].name)
		visual.mesh = importer.get_mesh()
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.layers = 0
		pivots[index].add_child(visual)
		proxies.append(visual)
	# Spread the small camera-distance checks across actors, including while the
	# physics simulation is paused for the inspector's independent camera.
	_timer = float(posmod(str(actor.actor_id).hash(), 10)) * 0.01

func _collect(node: Node, faded_meshes: Array) -> void:
	var fade_hidden: bool = node is GeometryInstance3D and faded_meshes.has(node)
	if node is Node3D and not node.visible and not fade_hidden:
		return # Hidden binoculars/cups must not reappear in the distant bake.
	if node is MeshInstance3D and node.mesh != null and (node.visible or fade_hidden):
		originals.append(node)
		original_layers.append(node.layers)
		original_shadows.append(node.cast_shadow)
	for child in node.get_children():
		_collect(child, faded_meshes)

func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or not is_instance_valid(actor):
		return
	_timer = 0.1
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		refresh(camera.global_position)

func refresh(camera_position: Vector3) -> void:
	if not supported:
		return
	var distance: float = actor.global_position.distance_to(camera_position)
	var force_full: bool = not enabled or actor.combat_override or actor.dead or actor._speech_remaining > 0.0
	_set_far(not force_full and distance > (NEAR_DISTANCE if far else FAR_DISTANCE))
	var shadows: bool = not enabled or distance < SHADOW_DISTANCE
	if shadows != _shadows:
		_shadows = shadows
		for index in originals.size():
			originals[index].cast_shadow = original_shadows[index] if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func force_full() -> void:
	_set_far(false)

func _set_far(value: bool) -> void:
	if far == value:
		return
	far = value
	for index in originals.size():
		originals[index].layers = 0 if far else original_layers[index]
	for proxy in proxies:
		proxy.layers = original_layers[0] if far and not original_layers.is_empty() else 0

func set_fade(value: float) -> void:
	for proxy in proxies:
		proxy.transparency = value
		proxy.visible = value < 0.999

func animation_due(delta: float) -> bool:
	_animation_time += delta
	if not far or _animation_time >= 0.05:
		_animation_time = fmod(_animation_time, 0.05)
		return true
	return false

func _append_surface(data: Dictionary, source: MeshInstance3D, surface: int, relative: Transform3D) -> bool:
	var material: Material = source.get_active_material(surface)
	var modular: bool = material is ShaderMaterial and material.shader == People.SHADER
	var color := Color.WHITE
	var finish := Vector2(0.88, 0.0)
	if modular:
		pass
	elif material is ShaderMaterial and material.shader == ClayLib.SHADER:
		var albedo: Variant = material.get_shader_parameter("albedo")
		if not albedo is Color:
			return false
		color = albedo
		var roughness: Variant = material.get_shader_parameter("roughness")
		var metallic: Variant = material.get_shader_parameter("metallic")
		finish = Vector2(float(roughness) if roughness != null else 0.86, float(metallic) if metallic != null else 0.0)
	elif material is StandardMaterial3D and material.albedo_texture == null and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and not material.emission_enabled:
		color = material.albedo_color
		finish = Vector2(material.roughness, material.metallic)
	else:
		return false
	var arrays: Array = source.mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	if normals.size() != vertices.size():
		return false
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if indices.is_empty():
		for index in vertices.size():
			indices.append(index)
	if indices.size() % 3 != 0:
		return false
	var look: Dictionary = {}
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	if modular:
		var roster_index: int = int(source.get_instance_shader_parameter("roster_override"))
		look = People.roster()[clampi(roster_index, 0, People.roster().size() - 1)]
		uv = arrays[Mesh.ARRAY_TEX_UV]
		uv2 = arrays[Mesh.ARRAY_TEX_UV2]
	var remap: Dictionary = {}
	var normal_basis := relative.basis.inverse().transposed()
	var winding := [0, 2, 1] if relative.basis.determinant() < 0.0 else [0, 1, 2]
	for triangle in range(0, indices.size(), 3):
		if modular and not _component_visible(roundi(uv2[indices[triangle]].x), look):
			continue
		for offset in winding:
			var index: int = indices[triangle + offset]
			if not remap.has(index):
				var point := vertices[index]
				var vertex_color := color
				var vertex_normal := normals[index]
				var vertex_finish := finish
				if modular:
					var fitted := People.bake_rig_vertex(look, point, vertex_normal, uv2[index], str(source.get_parent().name))
					point = fitted.point
					vertex_normal = fitted.normal
					var slot := roundi(uv[index].x)
					var color_slot := 8 if slot == 1 and int(look.garment_style) in [6,7] and uv2[index].y < -2.5 else slot
					vertex_color = _modular_color(color_slot, look)
					vertex_finish.x = .72 if slot == 0 else (.78 if slot == 3 else (.68 if slot == 4 else .86))
				elif material is StandardMaterial3D and material.vertex_color_use_as_albedo and arrays[Mesh.ARRAY_COLOR] != null:
					vertex_color *= arrays[Mesh.ARRAY_COLOR][index]
				remap[index] = data.vertices.size()
				data.vertices.append(relative * point)
				data.normals.append((normal_basis * vertex_normal).normalized())
				data.colors.append(vertex_color)
				data.finish.append(vertex_finish)
			data.indices.append(int(remap[index]))
	return true

static func _component_visible(component: int, look: Dictionary) -> bool:
	if component >= 1 and component <= 12:
		return component == int(look.hair_style) + 1
	if component >= 20 and component <= 28:
		return component == int(look.garment_style) + 20
	if component == 29:
		return int(look.garment_style) in [1,3,4,6]
	return component != 40 or float(look.beard) > 0.5

static func _modular_color(slot: int, look: Dictionary) -> Color:
	var linear_renderer := RenderingServer.get_current_rendering_method() != "gl_compatibility"
	var skin := Color(str(look.skin))
	var top := Color(str(look.top))
	if linear_renderer:
		skin = skin.srgb_to_linear()
		top = top.srgb_to_linear()
	var linear := skin
	match slot:
		1: linear = top
		2, 3, 4, 8:
			var key: String = {2: "pants", 3: "hair", 4: "shoes", 8: "accent"}[slot]
			linear = Color(str(look[key]))
			if linear_renderer:
				linear = linear.srgb_to_linear()
		5: linear = Color(0.84, 0.82, 0.76)
		6: linear = Color(0.022, 0.014, 0.009)
		7: linear = skin * Color(0.72, 0.49, 0.49)
		9: linear = top * Color(0.64, 0.64, 0.64)
		10: linear = Color(0.009, 0.008, 0.008)
		11: linear = Color(0.18, 0.12, 0.07)
		12: linear = Color(0.42, 0.40, 0.35)
	# Compatibility outputs the shader palette directly; the LOD shader only
	# decodes vertex colors in Forward+/Mobile, matching their linear pipeline.
	return linear.linear_to_srgb() if linear_renderer else linear
