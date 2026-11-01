extends Node
## Run headless with the standard isolated project profile. All checkpoint writes
## below target the explicit project-owned fixture, never the actual user slot.
const Save := preload("res://scripts/city/city_world_save.gd")
var passes := 0
var failures := 0
var fixture := ""

class MissionSchemaFixture extends Node3D:
	var schema: Dictionary = {}
	var can_restore := true
	func save_schema() -> Dictionary:
		return schema
	func preflight_restore(_state: Dictionary) -> bool:
		return can_restore

func check(value: bool, label: String) -> void:
	print("[city_world_save] %s %s" % ["PASS" if value else "FAIL", label])
	if value:
		passes += 1
	else:
		failures += 1

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	fixture = ProjectSettings.globalize_path("res://../.work/render-audit/save-test-profile/world.json")
	DirAccess.make_dir_recursive_absolute(fixture.get_base_dir())
	_cleanup()
	get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	await frames(4)
	var level: Node = get_tree().current_scene
	for i in 700:
		if level != null and level.get("level_ready") == true:
			break
		await frames(1)
		level = get_tree().current_scene
	if level == null or level.get("residents") == null:
		check(false, "world initialized")
		_finish()
		return
	level.pause_exploring()
	var original_block_score: int = G.S.score
	var provider := Save.new()
	level.add_child(provider)
	provider.setup(level)
	check(not provider.enabled, "automatic persistence disabled for validation")
	provider.setup(level, fixture)
	check(provider.enabled and provider.path == fixture, "explicit fixture enables isolated persistence")
	check(not provider.read_snapshot().ok, "missing slot starts clean")
	var state: Dictionary = provider.snapshot_state()
	if state.is_empty():
		check(false, "stable grounded startup checkpoint")
		_finish()
		return
	check(provider.validate_snapshot(state).is_empty() and state.residents.residents.size() == 40, "forty stable IDs and complete schema")
	check(state.version == Save.VERSION and state.deaths == {"version": 1, "dead": []} and state.inventory is Dictionary and state.progression is Dictionary
		and state.get("vehicles") is Dictionary, "v4 checkpoint includes death registry, inventory, progression and remembered vehicles")
	var old_state: Dictionary = state.duplicate(true)
	old_state.version = 1
	old_state.erase("deaths")
	check(provider.validate_snapshot(old_state).is_empty(), "v1 world checkpoints migrate without resetting progress")
	var legacy_roster: Dictionary = state.duplicate(true)
	for id in legacy_roster.residents.residents.keys():
		if id not in Save.Residents.LEGACY_RESIDENT_IDS:
			legacy_roster.residents.residents.erase(id)
	check(legacy_roster.residents.residents.size() == 20 and provider.validate_snapshot(legacy_roster).is_empty(), "exact original twenty resident IDs remain loadable after forty-person expansion")
	var legacy_v1: Dictionary = legacy_roster.duplicate(true)
	legacy_v1.version = 1
	legacy_v1.erase("deaths")
	check(provider.validate_snapshot(legacy_v1).is_empty(), "original v1 world with twenty residents remains migration compatible")
	var truncated_roster: Dictionary = state.duplicate(true)
	truncated_roster.residents.residents.erase(Save.Residents.LEGACY_RESIDENT_IDS[0])
	check(provider.validate_snapshot(truncated_roster) == "resident roster mismatch", "arbitrary thirty-nine resident save is rejected")
	var mixed_roster: Dictionary = legacy_roster.duplicate(true)
	mixed_roster.residents.residents.erase(Save.Residents.LEGACY_RESIDENT_IDS[0])
	for id in state.residents.residents:
		if id not in Save.Residents.LEGACY_RESIDENT_IDS:
			mixed_roster.residents.residents[id] = state.residents.residents[id]
			break
	check(mixed_roster.residents.residents.size() == 20 and provider.validate_snapshot(mixed_roster) == "resident roster mismatch", "twenty mixed old/new IDs cannot impersonate a legacy checkpoint")
	var invalid_death: Dictionary = state.duplicate(true)
	invalid_death.erase("deaths")
	check(provider.validate_snapshot(invalid_death) == "missing death registry", "v2 cannot silently omit deaths")
	invalid_death = state.duplicate(true)
	invalid_death.deaths.dead = ["resident", "resident"]
	check(not provider.validate_snapshot(invalid_death).is_empty(), "duplicate death identities rejected")
	invalid_death.deaths.dead = ["not_a_real_person"]
	check(not provider.validate_snapshot(invalid_death).is_empty(), "unknown death identities rejected")
	invalid_death.deaths = {"version": 2, "dead": []}
	check(not provider.validate_snapshot(invalid_death).is_empty(), "future death registry preserved by refusal")
	var authored_schema: Dictionary = level.missions.save_schema()
	var schema_matches := true
	for definition in level.missions.CASES:
		schema_matches = schema_matches and authored_schema[definition.id].reward == definition.reward and authored_schema[definition.id].stages == level.missions.case_steps(definition.id).size()
	check(schema_matches, "reward and stage validation derives from authored mission data")
	check(provider.write_snapshot(state) == OK and provider.read_snapshot().ok, "first atomic write and parse")
	var second: Dictionary = state.duplicate(true)
	second.clock.total_minutes += 75.0
	second.equipment = {"health": 63.0, "weapon": "pistol", "ammo": 4, "reserve": 27}
	second.inventory.equipped = "pistol"
	second.inventory.weapons.pistol = {"owned": true, "ammo": 4, "reserve": 27}
	check(provider.write_snapshot(second) == OK, "replace existing Windows slot atomically")
	check(provider._read(fixture + ".bak").ok and FileAccess.get_file_as_string(fixture + ".bak") == JSON.stringify(state), "backup retains preceding valid checkpoint byte for byte")
	var bad: Dictionary = second.duplicate(true)
	bad.version = 99
	check(provider.validate_snapshot(bad) == "unsupported version", "future schema rejected")
	bad = second.duplicate(true)
	bad.equipment.ammo = 13
	check(not provider.validate_snapshot(bad).is_empty(), "oversized magazine rejected")
	bad = second.duplicate(true)
	bad.equipment.health = INF
	check(not provider.validate_snapshot(bad).is_empty(), "non-finite health rejected")
	bad = second.duplicate(true)
	bad.equipment.reserve = -1
	check(not provider.validate_snapshot(bad).is_empty(), "negative reserve rejected")
	bad = second.duplicate(true)
	bad.equipment.weapon = "unknown"
	check(not provider.validate_snapshot(bad).is_empty(), "unknown weapon rejected")
	bad = second.duplicate(true)
	bad.version = 1
	bad.erase("equipment")
	check(provider.validate_snapshot(bad).is_empty(), "early v1 checkpoints without equipment remain readable")
	bad = second.duplicate(true)
	bad.player.position = [1.0, 2.0]
	check(not provider.validate_snapshot(bad).is_empty(), "malformed vector rejected")
	bad = second.duplicate(true)
	bad.player.position = [100000.0, 0.0, 100000.0]
	check(not provider.validate_snapshot(bad).is_empty(), "out of bounds rejected")
	bad = second.duplicate(true)
	bad.clock.total_minutes = "later"
	check(not provider.validate_snapshot(bad).is_empty(), "wrong clock type rejected")
	bad = second.duplicate(true)
	bad.residents.residents["unknown"] = bad.residents.residents.values()[0]
	check(not provider.validate_snapshot(bad).is_empty(), "unknown resident rejected")
	bad = second.duplicate(true)
	bad.missions.completed_ids = ["lost_satchel", "lost_satchel"]
	bad.missions.score = 200
	check(not provider.validate_snapshot(bad).is_empty(), "duplicate reward IDs rejected")
	bad = second.duplicate(true)
	bad.missions.score = 850
	check(not provider.validate_snapshot(bad).is_empty(), "unearned score rejected")
	bad = second.duplicate(true)
	bad.walk.visited = ["unknown"]
	bad.walk.route_index = 1
	check(not provider.validate_snapshot(bad).is_empty(), "unknown ledger stop rejected")
	bad = second.duplicate(true)
	bad.progression.money = -1
	check(not provider.validate_snapshot(bad).is_empty(), "negative cash cannot enter save")
	bad = second.duplicate(true)
	bad.inventory.weapons.uzi.owned = true
	bad.inventory.weapons.uzi.ammo = 9999
	check(not provider.validate_snapshot(bad).is_empty(), "oversized secondary weapon magazine rejected")
	bad = second.duplicate(true)
	bad.erase("progression")
	check(not provider.validate_snapshot(bad).is_empty(), "v3 cannot silently drop wallet and alignment")
	var before := FileAccess.get_file_as_string(fixture)
	check(provider.write_snapshot(bad) == ERR_INVALID_DATA and FileAccess.get_file_as_string(fixture) == before, "bad snapshot preserves good file")
	provider.path = fixture.get_base_dir() + "/missing-parent/world.json"
	check(provider.write_snapshot(second) != OK and FileAccess.get_file_as_string(fixture) == before, "failed write preserves existing checkpoint")
	provider.path = fixture
	_write_raw(fixture, "{truncated")
	check(provider.read_snapshot().get("backup", false), "malformed primary recovers valid backup")
	check(provider.write_snapshot(second) == OK and provider._read(fixture + ".bak").ok, "repair keeps valid backup")
	var preserved: Array = provider.get_status().preserved_files
	check(not preserved.is_empty() and FileAccess.get_file_as_string(preserved[-1]) == "{truncated", "repaired primary retained byte for byte in rejected archive")
	bad = second.duplicate(true)
	bad.version = 99
	_write_raw(fixture, JSON.stringify(bad))
	check(not provider.read_snapshot().ok and provider.get_status().write_blocked, "future primary blocks fallback and writes")
	check(provider.write_snapshot(second) == ERR_UNAVAILABLE, "future slot never overwritten")
	provider._write_blocked = false
	bad = second.duplicate(true)
	bad.deaths.version = 2
	_write_raw(fixture, JSON.stringify(bad))
	_write_raw(fixture + ".bak", JSON.stringify(second))
	check(not provider.read_snapshot().ok and provider.write_snapshot(second) == ERR_UNAVAILABLE and FileAccess.get_file_as_string(fixture) == JSON.stringify(bad), "future nested death schema blocks rollback to older valid backup")
	bad = second.duplicate(true)
	bad.version = 99
	provider._write_blocked = false
	_write_raw(fixture, "{truncated")
	_write_raw(fixture + ".bak", JSON.stringify(bad))
	check(not provider.read_snapshot().ok and provider.get_status().write_blocked, "future backup also blocks automatic rollback")
	check(provider.write_snapshot(second) == ERR_UNAVAILABLE, "future backup retained through attempted save")
	provider._write_blocked = false
	_cleanup()
	_write_raw(fixture + ".tmp", JSON.stringify(second))
	check(provider.read_snapshot().get("source", "") == "temporary", "orphan validated temporary checkpoint recovered")
	check(provider.write_snapshot(state) == OK and provider._read(fixture + ".bak").ok and FileAccess.get_file_as_string(fixture + ".bak") == JSON.stringify(second), "sole temporary checkpoint backed up byte for byte before reuse")
	_cleanup()
	_write_raw(fixture + ".tmp", JSON.stringify(bad))
	check(not provider.read_snapshot().ok and provider.write_snapshot(state) == ERR_UNAVAILABLE, "future temporary checkpoint protected before opening write file")
	provider._write_blocked = false
	_cleanup()
	_write_raw(fixture, "{unrecoverable")
	check(not provider.load_state().ok and provider.write_snapshot(state) == ERR_UNAVAILABLE and FileAccess.get_file_as_string(fixture) == "{unrecoverable", "unrecoverable invalid save remains untouched after failed load")
	provider._write_blocked = false
	var mission_provider: Node3D = level.missions
	var changed_schema := MissionSchemaFixture.new()
	changed_schema.schema = authored_schema.duplicate(true)
	changed_schema.schema.lost_satchel.reward += 1
	var earned: Dictionary = second.duplicate(true)
	earned.missions = {"active_id": "", "stage": 0, "completed_ids": ["lost_satchel"], "score": authored_schema.lost_satchel.reward}
	_write_raw(fixture, JSON.stringify(earned))
	_write_raw(fixture + ".bak", JSON.stringify(earned))
	level.missions = changed_schema
	check(not provider.load_state().ok and provider.write_snapshot(state) == ERR_UNAVAILABLE and FileAccess.get_file_as_string(fixture) == JSON.stringify(earned), "changed authored reward refuses incompatible save without replacing it")
	level.missions = mission_provider
	provider._write_blocked = false
	_write_raw(fixture + ".bak", JSON.stringify(state))
	_write_raw(fixture, JSON.stringify(second))
	level.world_time.total_minutes = 1.0
	changed_schema.schema = authored_schema.duplicate(true)
	changed_schema.can_restore = false
	level.missions = changed_schema
	var refused: Dictionary = provider.load_state()
	check(not refused.ok and not refused.get("partial", true) and level.world_time.total_minutes == 1.0, "failed mission preflight leaves world state untouched")
	level.missions = mission_provider
	changed_schema.free()
	provider._write_blocked = false
	var restored: Dictionary = provider.load_state()
	check(restored.ok and is_equal_approx(level.world_time.total_minutes, float(second.clock.total_minutes)), "clock resumes from checkpoint")
	var restored_inventory: Dictionary = level.combat.equipment_snapshot()
	check(is_equal_approx(level.combat.health, 63.0) and restored_inventory.weapons == second.inventory.weapons
		and restored_inventory.equipped == "fists" and level.combat.weapon == "fists" and not level.combat.player_offense_enabled(),
		"legacy health, ownership and all ammunition persist exactly while pacifist policy holsters the weapon")
	check(not level.combat._gun.visible and not level.combat.aiming and level.combat.reloading == 0.0
		and not level.combat._trigger_held and level.combat._attack_elapsed < 0.0,
		"restored legacy weapon stays hidden with no active attack state")
	check(restored.residents.restored == 40, "all saved residents restore grounded")
	var overlapping: Dictionary = second.residents.duplicate(true)
	var first_id: String = str(overlapping.residents.keys()[0])
	var player_point: Vector3 = level.player.global_position
	overlapping.residents[first_id].position = [player_point.x, player_point.y, player_point.z]
	var fallback: Dictionary = level.residents.restore_state(overlapping)
	check(fallback.fallback >= 1 and level.residents.actors[first_id].global_position.distance_to(player_point) > 0.66, "resident restore refuses player overlap even while paused")
	check(provider.safe_player_position(level.player.global_position + Vector3.UP * 10.0).is_empty(), "airborne checkpoint rejected")
	level.combat.downed = 1.0
	check(provider.save_state() == ERR_BUSY, "active combat preserves stable checkpoint")
	level.combat.downed = 0.0
	var completed := {"active_id": "", "stage": 0, "completed_ids": ["lost_satchel"], "score": 100}
	check(level.missions.restore_state(completed) and level.missions.score == 100, "completed case derives exact reward")
	check(level.missions.restore_state(completed) and level.missions.score == 100 and not level.missions.start_case("lost_satchel"), "repeat load cannot duplicate completed reward")
	check(not level.missions.commit_dialogue_action({"kind": "case_step", "id": "lost_satchel", "stage": 2}), "stale completion callback refused after restore")
	for id in ["lost_satchel", "missing_tools", "dumping"]:
		var stage := 2 if id == "lost_satchel" else 3
		var resumed := {"active_id": id, "stage": stage, "completed_ids": [], "score": 0}
		var ok: bool = level.missions.restore_state(resumed)
		check(ok and level.missions.active_id == id and level.missions.stage == stage and level.missions.score == 0, id + " resumes progress without reward replay")
		check(ok and not level.missions._clue.visible and level.missions._clue_body.collision_layer == 0, id + " restores collected/cleared clue state")
	var resumed_state: Dictionary = second.duplicate(true)
	resumed_state.missions = level.missions.snapshot_state()
	check(provider.write_snapshot(resumed_state) == OK, "in-progress case written with world checkpoint")
	level.missions.cancel_case()
	var fresh := Save.new()
	level.add_child(fresh)
	fresh.setup(level, fixture)
	check(fresh.load_state().ok and level.missions.active_id == "dumping" and level.missions.stage == 3, "fresh provider resumes persisted case from disk")
	var saves_before: int = provider.save_count
	provider.tick(60.0)
	check(provider.save_count == saves_before, "paused menus do not advance autosave")
	check(G.S.score == original_block_score, "chapter restore leaves original-block reward state unchanged")
	level.missions.cancel_case()
	check(level.missions.start_case("lost_satchel"), "live contact can start a case before death")
	var contact = level.npcs.get_actor("resident")
	contact.set_enabled(true)
	var death_events: Array[String] = []
	level.combat.actor_died.connect(func(id: String): death_events.append(id))
	var progression_before_death: Dictionary = level.progression.snapshot_state().duplicate(true)
	var player_hits_before: int = level.combat.hits_landed
	check(not level.combat.player_offense_enabled() and not level.combat._damage_target(contact, 1000.0, "shot")
		and not level.combat.is_actor_dead("resident"), "player-caused lethal hit remains blocked by pacifist policy")
	# Use the same authoritative NPC-damage entry point as police assistance;
	# this is a persistence fixture, not a claim of a player attack or a police encounter.
	var officer: Node3D = level.npcs.get_actor("officer")
	check(level.combat.receive_police_round(contact, 1000.0, officer.global_position + Vector3.UP, "officer")
		and death_events == ["resident"] and level.combat.is_actor_dead("resident"), "authoritative police damage emits actual contact death event")
	check(level.combat.hits_landed == player_hits_before and level.progression.snapshot_state() == progression_before_death,
		"NPC-caused death does not attribute a player hit, change wallet or alignment")
	check(level.combat.restore_deaths({"version": 1, "dead": [first_id]}), "scheduled resident death applied")
	check(level.missions.active_id.is_empty() and level.missions.score == 0, "dead required contact closes active case without a reward")
	check(not level.npcs.actor_position("resident").is_finite() and not level.missions.start_case("lost_satchel"), "dead contacts are neither interactable nor reusable")
	var death_state: Dictionary = second.duplicate(true)
	death_state.missions = {"active_id": "", "stage": 0, "completed_ids": [], "score": 0}
	death_state.deaths = level.combat.death_snapshot()
	check(provider.validate_snapshot(death_state).is_empty() and provider.write_snapshot(death_state) == OK, "death identities written in validated world slot")
	check(fresh.load_state().ok and level.combat.is_actor_dead("resident") and level.residents.actors[first_id].dead, "disk restore retains contact and daily resident deaths")
	level.residents.actors[first_id].set_enabled(true)
	check(not level.residents.actors[first_id].enabled, "schedule or LOD activation cannot revive dead resident")
	death_state.missions.active_id = "lost_satchel"
	check(provider.validate_snapshot(death_state) == "case requires deceased contact", "impossible saved case cannot restore alongside dead required contact")
	check(level.combat.restore_deaths({"version": 1, "dead": ["lookout", "officer"]}), "past case contacts can remain dead")
	var remaining := {"active_id": "dumping", "stage": 3, "completed_ids": [], "score": 0}
	check(level.missions.preflight_restore(remaining) and level.missions.restore_state(remaining), "remaining clue-only stage restores without resurrecting past contacts")
	# A new level starts with a genuinely empty registry. Re-loading the same
	# already-dead actors would not prove that persisted identities were applied.
	get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	await frames(4)
	level = get_tree().current_scene
	for i in 1000:
		if level != null and level.get("level_ready") == true:
			break
		await frames(1)
		level = get_tree().current_scene
	check(level != null and level.get("level_ready") == true, "fresh world initialized for death restore")
	if level != null and level.get("level_ready") == true:
		level.pause_exploring()
		check(not level.combat.is_actor_dead("resident") and not level.residents.actors[first_id].dead, "fresh world has no inherited in-memory deaths")
		var disk_provider := Save.new()
		level.add_child(disk_provider)
		disk_provider.setup(level, fixture)
		check(disk_provider.load_state().ok and level.combat.is_actor_dead("resident") and level.residents.actors[first_id].dead, "fresh world restores both deaths from disk alone")
	_cleanup()
	_finish()

func _write_raw(path: String, contents: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(contents)
	file.close()

func _cleanup() -> void:
	# Only this fixture basename in its explicit project directory, no recursion.
	for filename in DirAccess.get_files_at(fixture.get_base_dir()):
		if filename == fixture.get_file() or filename.begins_with(fixture.get_file() + "."):
			DirAccess.remove_absolute(fixture.get_base_dir().path_join(filename))

func _finish() -> void:
	print("[city_world_save] %d passed, %d failed" % [passes, failures])
	get_tree().quit(1 if failures else 0)
