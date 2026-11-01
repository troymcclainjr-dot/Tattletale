extends RefCounted
## Authored fictional population appearance, never a gameplay characteristic.
## Immutable birth IDs determine appearance; current ordering, deaths, activities,
## placement and save state do not participate. No per-frame application.
const DATA_PATH := "res://assets/data/pen_lucy_population_appearance.json"
const ModularPeople := preload("res://scripts/city/city_modular_people.gd")
const CROWD_TOTAL := 1200
const CROWD_BLACK := 964
const BLACK_SKIN := ["482b20", "563626", "65412e", "754b34", "8a5a3c", "9b6849", "b0805c", "c68e62"]
const OTHER_SKIN := ["e8b48a", "d5a279", "c48e64", "ecc0a0", "a87550", "f0c8a8"]
static var _authored: Dictionary = {}
# Append-only roster indices preserve the original authored twenty save mappings.
const BLACK_ROSTER := [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35]
const OTHER_ROSTER := [16,17,18,19,36,37,38,39]

static func profile(identity: String) -> Dictionary:
	if identity.begins_with("crowd_"):
		var ordinal := int(identity.trim_prefix("crowd_"))
		assert(identity == "crowd_%d" % ordinal and ordinal >= 0 and ordinal < CROWD_TOTAL)
		# A permutation of all 1200 birth ordinals spreads the exact quota across
		# the city without regrouping people by race or changing any birth ID.
		var rank := (ordinal * 719 + 137) % CROWD_TOTAL
		var index: int = BLACK_ROSTER[rank % BLACK_ROSTER.size()] if rank < CROWD_BLACK else OTHER_ROSTER[(rank - CROWD_BLACK) % OTHER_ROSTER.size()]
		var look: Dictionary = ModularPeople.roster()[index]
		return {"id": identity, "identity_group": str(look.identity_group), "skin": str(look.skin), "roster_index": index, "roster_id": str(look.id), "apply_skin": true, "source": "birth_id_modular_roster_v3"}
	if _authored.is_empty():
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		for entry in data.identities:
			_authored[str(entry.id)] = entry
	return _authored.get(identity, {}).duplicate()

## Legacy/fixture actors need not know the modular roster field. Authored indices
## win; otherwise hash only the immutable identity, never order or world state.
static func modular_index(identity: String, appearance: Dictionary = {}) -> int:
	var count := ModularPeople.roster().size()
	for resolved in [appearance, profile(identity)]:
		# Prefer a stable style ID when present; integer-only v2 saves remain valid.
		var roster_id := str(resolved.get("roster_id", ""))
		if not roster_id.is_empty():
			for i in count:
				if str(ModularPeople.roster()[i].id) == roster_id:
					return i
		var value: Variant = resolved.get("roster_index", -1)
		if (value is int or value is float) and is_finite(float(value)):
			var index := int(value)
			if float(index) == float(value) and index >= 0 and index < count:
				return index
	var hash_value: int = 5381
	for byte in identity.to_utf8_buffer():
		hash_value = ((hash_value * 33) ^ int(byte)) & 0x7fffffff
	return hash_value % count

static func skin_linear(appearance: Dictionary) -> Color:
	return Color(str(appearance.skin)).srgb_to_linear()

## Only generic patrol instances are recolored. Imported shared materials and
## the original Officer Dan/Steve characters remain untouched. Exact authored
## base-skin albedo identifies skin surfaces; clothing/hair/lips are retained.
static func apply_patrol_skin(node: Node, original_skin: Color, replacement: Color) -> int:
	var changed := 0
	if node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count():
			var material: Material = node.get_active_material(surface)
			if not material is ShaderMaterial:
				continue
			var albedo: Variant = material.get_shader_parameter("albedo")
			if not albedo is Color or not albedo.is_equal_approx(original_skin):
				continue
			var own: ShaderMaterial = material.duplicate()
			own.set_shader_parameter("albedo", replacement)
			node.set_surface_override_material(surface, own)
			changed += 1
	for child in node.get_children():
		changed += apply_patrol_skin(child, original_skin, replacement)
	return changed
