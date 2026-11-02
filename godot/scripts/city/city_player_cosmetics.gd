extends RefCounted
## Recolor only explicitly identified clothing, with instance-local materials.
## Exported Cast clay is ShaderMaterial(albedo); primitive fallback meshes
## use material_override. Preserve both precedence paths and exact originals.
## The export joins the bandana into Head_Mesh with its own named surface.
const EXPORTED_BANDANA_MATERIAL := "clay_c4162a_r85"
static func bandana(root: Node, html: String) -> void:
	if root == null:
		return
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null:
			continue
		var selected := _bandana_surfaces(mesh)
		if selected.is_empty():
			continue
		if str(mesh.get_meta("shop_bandana_color", "")) == html:
			continue
		if not mesh.has_meta("shop_bandana_original"):
			var surfaces: Array = []
			for surface in mesh.mesh.get_surface_count():
				surfaces.append({"override": mesh.get_surface_override_material(surface), "active": mesh.get_active_material(surface)})
			mesh.set_meta("shop_bandana_original", {"override": mesh.material_override, "surfaces": surfaces})
		var original: Dictionary = mesh.get_meta("shop_bandana_original")
		if html.is_empty():
			mesh.material_override = original.override
			for surface in selected:
				mesh.set_surface_override_material(surface, original.surfaces[surface].override)
		elif original.override != null:
			# An overall override wins over per-surface overrides (Prim.M).
			mesh.material_override = _tinted(original.override, Color.html(html))
		else:
			for surface in selected:
				mesh.set_surface_override_material(surface, _tinted(original.surfaces[surface].active, Color.html(html)))
		mesh.set_meta("shop_bandana_color", html)

static func _bandana_surfaces(mesh: MeshInstance3D) -> Array[int]:
	var result: Array[int] = []
	if str(mesh.name).begins_with("Bandana"):
		for surface in mesh.mesh.get_surface_count():
			result.append(surface)
	elif str(mesh.name) == "Head_Mesh" and mesh.material_override == null:
		for surface in mesh.mesh.get_surface_count():
			var original := mesh.mesh.surface_get_material(surface)
			if original != null and original.resource_name == EXPORTED_BANDANA_MATERIAL:
				result.append(surface)
	return result

static func _tinted(original: Material, color: Color) -> Material:
	if original is StandardMaterial3D:
		var material := original.duplicate() as StandardMaterial3D
		material.albedo_color = color
		return material
	if original is ShaderMaterial and original.get_shader_parameter("albedo") is Color:
		var material := original.duplicate() as ShaderMaterial
		material.set_shader_parameter("albedo", color)
		return material
	return original
