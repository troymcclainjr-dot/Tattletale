extends RefCounted
## City-only surface finishes and compact batches of decorative, non-blocking litter.
const SURFACE := preload("res://assets/materials/city_surface.gdshader")
const ROAD_WEAR := preload("res://assets/materials/city_road_wear.gdshader")
const Windows := preload("res://scripts/city/city_windows.gd")
const BRICK := ["6e3a30", "9a5a44", "a8644a", "8a4a3a"]
const CONCRETE := ["9a968c", "eeeae0", "8a8a90", "c8c4b8", "a8a49a", "b4a68a", "d8d0c0"]
const TRIM := ["f4f0e6", "e2d4b4", "3f5a44", "5a3a28", "8a2a24"]
const EARTH := ["6a8a3a", "7d7a70", "6e5a3c"]
const UNTOUCHED := ["3e3e44", "a8a8ae", "6a5846", "5a5a62"]
## Each city shader keeps its calibrated specular response behind this define.
## The legacy profile renames it on the shared Shader resources, never in a
## material, so cached cells and palette meshes always follow the running profile.
const CALIBRATED_DEFINE := "#define CITY_CALIBRATED_FINISHES"
const LEGACY_DEFINE := "#define CITY_LEGACY_FINISHES"

## Surface kind for a ClayLib finish name; 0 keeps the imported material.
static func classify(material_name: String) -> int:
	var parts := material_name.split("_")
	if parts.size() < 3 or parts[0] != "clay":
		return 0
	var hex: String = parts[1]
	if hex in TRIM:
		return 6
	if hex in BRICK:
		return 1
	if hex in CONCRETE:
		return 2
	if hex == "3a3a40":
		return 3
	if hex in EARTH:
		return 5
	if hex in UNTOUCHED:
		return 0
	return 4

static func legacy_finishes_requested() -> bool:
	return "--legacy-city-finishes" in OS.get_cmdline_args() or "--legacy-city-finishes" in OS.get_cmdline_user_args()

static func legacy_code(code: String) -> String:
	return code.replace(CALIBRATED_DEFINE, LEGACY_DEFINE)

## Whole-process A/B baseline: previous shader output with identical materials,
## uniforms, surfaces and draw layout. Call before the city first renders.
static func use_legacy_finishes() -> void:
	for shader in [SURFACE, Windows.GLASS, ROAD_WEAR]:
		if shader.code.contains(CALIBRATED_DEFINE):
			shader.code = legacy_code(shader.code)

static func finish_profile() -> String:
	var active_shader: Shader = SURFACE
	return "legacy" if active_shader.code.contains(LEGACY_DEFINE) else "calibrated"

static func apply_materials(city: Node3D) -> Dictionary:
	if legacy_finishes_requested():
		use_legacy_finishes()
	var shared := {}
	var kinds := {}
	var count := 0
	var glass := Windows.glass_material()
	var glass_surfaces := 0
	for node in city.find_children("*", "MeshInstance3D", true, false):
		if node.mesh == null:
			continue
		var name_: String = str(node.name)
		# Leaves, metal, glass and roofs retain their original clean material response.
		if name_.begins_with("Trees"):
			continue
		for index in node.mesh.get_surface_count():
			var current: Material = node.mesh.surface_get_material(index)
			if current == null:
				continue
			if current.resource_name == Windows.GLASS_NAME:
				node.set_surface_override_material(index, glass)
				glass_surfaces += 1
				continue
			var kind := classify(current.resource_name)
			if kind == 0:
				continue
			var key: String = current.resource_name
			if not shared.has(key):
				var parts := key.split("_")
				var material := ShaderMaterial.new()
				material.shader = SURFACE
				material.resource_name = key
				material.set_shader_parameter("albedo", Color.html("#" + parts[1]))
				material.set_shader_parameter("roughness", clampf(float(parts[2].substr(1)) / 100.0, 0.0, 1.0))
				material.set_shader_parameter("surface_kind", kind)
				shared[key] = material
				kinds[kind] = int(kinds.get(kind, 0)) + 1
			# Per-instance overrides keep the optimizer's persisted base mesh clean.
			node.set_surface_override_material(index, shared[key])
			count += 1
	return {"weathered_surfaces": count, "shared_finishes": shared.size(), "rough_glass_surfaces": glass_surfaces,
		"finish_profile": finish_profile(), "finish_kinds": kinds}

func build_litter(level: Node3D) -> Dictionary:
	# All-map records and streaming now belong to CityYardDetails. Keep this
	# reporting hook so material/weathering callers never create duplicate litter.
	var provider = level.get("yard_details")
	if provider == null:
		return {"litter": 0, "draw_batches": 0, "collision_groups": 0, "provider": "pending"}
	var status: Dictionary = provider.get_status()
	return {"litter": int(status.get("audit", {}).get("litter", 0)),
		"draw_batches": int(status.get("active_batches", 0)), "collision_groups": 0,
		"provider": "CityYardDetails", "spatial_cells": int(status.get("cells", 0))}
