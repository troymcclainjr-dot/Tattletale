class_name ClayLib
## Builds the game's materials from the names the Blender assets give them
## (see blender/claykit.py): clay_RRGGBB_rNN, gloss_RRGGBB_rNN, metal_RRGGBB_rNN,
## glow_RRGGBB_eNN, glass_RRGGBB_aNN.
## In the editor (on import) each material is saved once to res://assets/materials/gen/
## and shared by every model that uses it. At runtime unknown names are built in memory.

const GEN_DIR := "res://assets/materials/gen"
const SHADER := preload("res://assets/materials/clay.gdshader")
const NORMAL_TEX := preload("res://assets/materials/clay_normal.png")
const MOTTLE_TEX := preload("res://assets/materials/clay_mottle.png")

static var _cache := {}


## Material for a convention name, or null if the name doesn't follow the convention.
static func material(mat_name: String) -> Material:
	if _cache.has(mat_name):
		return _cache[mat_name]
	var path := "%s/%s.tres" % [GEN_DIR, mat_name]
	var m: Material = null
	if ResourceLoader.exists(path):
		m = load(path)
	else:
		m = build(mat_name)
		if m and Engine.is_editor_hint():
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GEN_DIR))
			if ResourceSaver.save(m, path) == OK:
				m = load(path)
	if m:
		_cache[mat_name] = m
	return m


## Shortcut for code-built meshes: ClayLib.clay("#8a4a3a", 0.86)
static func clay(hex: String, rough := 0.86) -> Material:
	return material("clay_%s_r%d" % [hex.trim_prefix("#").to_lower(), roundi(rough * 100.0)])


static func glow(hex: String, strength := 1.5) -> Material:
	return material("glow_%s_e%d" % [hex.trim_prefix("#").to_lower(), roundi(strength * 10.0)])


static func build(mat_name: String) -> Material:
	var parts := mat_name.split("_")
	if parts.size() < 3 or parts[1].length() != 6 or not parts[1].is_valid_hex_number():
		return null
	var kind := parts[0]
	var col := Color.html("#" + parts[1])
	var num := float(parts[2].substr(1)) if parts[2].length() > 1 else 0.0
	match kind:
		"clay", "gloss", "metal":
			var sm := ShaderMaterial.new()
			sm.shader = SHADER
			sm.resource_name = mat_name
			sm.set_shader_parameter("albedo", col)
			sm.set_shader_parameter("roughness", clampf(num / 100.0, 0.0, 1.0))
			sm.set_shader_parameter("clay_normal", NORMAL_TEX)
			sm.set_shader_parameter("clay_mottle", MOTTLE_TEX)
			if kind == "gloss":
				sm.set_shader_parameter("print_amount", 0.3)
				sm.set_shader_parameter("mottle_amount", 0.35)
				sm.set_shader_parameter("sheen", 0.12)
			elif kind == "metal":
				sm.set_shader_parameter("metallic", 0.85)
				sm.set_shader_parameter("print_amount", 0.35)
				sm.set_shader_parameter("mottle_amount", 0.3)
				sm.set_shader_parameter("sheen", 0.08)
			return sm
		"glow":
			var gm := StandardMaterial3D.new()
			gm.resource_name = mat_name
			gm.albedo_color = col
			gm.roughness = 0.4
			gm.emission_enabled = true
			gm.emission = col
			gm.emission_energy_multiplier = maxf(num / 10.0, 0.0)
			return gm
		"glass":
			var tm := StandardMaterial3D.new()
			tm.resource_name = mat_name
			tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			tm.albedo_color = Color(col, clampf(num / 100.0, 0.0, 1.0))
			tm.roughness = 0.35
			tm.cull_mode = BaseMaterial3D.CULL_DISABLED
			return tm
	return null


## Swap every convention-named material under a node (used on import, and on any
## runtime-instanced scene that skipped the import script).
static func apply(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		var mesh: Mesh = node.mesh
		for i in mesh.get_surface_count():
			var cur: Material = mesh.surface_get_material(i)
			if cur == null:
				continue
			var nm := cur.resource_name
			if nm.is_empty() or cur is ShaderMaterial and cur.shader == SHADER:
				continue
			var m := material(nm)
			if m:
				mesh.surface_set_material(i, m)
	for c in node.get_children():
		apply(c)
