extends SceneTree
const Appearance := preload("res://scripts/city/city_population_appearance.gd")
var failures := 0
func _initialize() -> void:
	_watchdog.call_deferred()
	_run.call_deferred()
func _watchdog() -> void:
	await create_timer(30.0, true, false, true).timeout
	push_error("[modular_legacy] FAIL fixture did not finish within 30 seconds")
	quit(1)
func check(ok: bool, label: String) -> void:
	print("[modular_legacy] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
func _run() -> void:
	var actor_script: Script = load("res://scripts/city/city_resident_actor.gd")
	if actor_script == null or not actor_script.can_instantiate():
		check(false, "Actor script loads after autoload registration")
		quit(1)
		return
	var identity := "fixture_legacy_recovery_actor"
	var expected := Appearance.modular_index(identity)
	check(expected >= 0 and expected < 20 and expected == Appearance.modular_index(identity), "unknown legacy identity has deterministic valid roster")
	check(Appearance.modular_index(identity, {"skin": "663322"}) == expected, "partial appearance profile needs no roster field")
	check(Appearance.modular_index(identity, {"roster_index": -2}) == expected and Appearance.modular_index(identity, {"roster_index": 200}) == expected and Appearance.modular_index(identity, {"roster_index": "bad"}) == expected, "invalid optional roster indices fall back to stable identity")
	check(Appearance.modular_index(identity, {"roster_index": 7}) == 7, "valid explicit roster index remains authoritative")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Appearance.DATA_PATH))
	var canonical := true
	for entry in data.identities:
		if entry.has("roster_index"):
			canonical = canonical and Appearance.modular_index(str(entry.id)) == int(entry.roster_index) and Appearance.modular_index(str(entry.id), {"skin": "663322"}) == int(entry.roster_index)
	for ordinal in 1200:
		var id := "crowd_%d" % ordinal
		canonical = canonical and Appearance.modular_index(id) == int(Appearance.profile(id).roster_index)
	check(canonical, "all existing authored daily and ambient mappings remain unchanged")
	var owner_level := Node3D.new()
	root.add_child(owner_level)
	for index in 2:
		var actor = actor_script.new()
		owner_level.add_child(actor)
		var definition := {"id": identity, "name": "Legacy fixture", "speed": 1.2}
		if index == 0:
			definition.appearance = {"h": 1.82, "skin": "663322"}
		actor.build_resident(owner_level, definition)
		actor.puppet.pose({"lean": 0.1, "nod": 0.1})
		var surface: MeshInstance3D = actor.puppet.g.get_node("Rig/Body/BodySurface")
		check(actor.puppet.body != null and actor.puppet.g.has_node("Rig/Body/Head") and int(surface.get_instance_shader_parameter("roster_override")) == expected, "legacy actor %d builds a complete bound rig with same identity appearance" % index)
		check(is_equal_approx(actor.puppet.H, 1.82 if index == 0 else 1.7), "authored height retained or missing legacy height defaults safely")
	owner_level.free()
	quit(1 if failures else 0)
