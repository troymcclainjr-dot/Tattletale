extends Node
## Provider-contract fixtures only. No city model, vehicle, rendering or user save.
const Save := preload("res://scripts/city/city_world_save.gd")
var failures := 0
var passes := 0

class PlayerFixture extends Node3D:
	var impact_recovery := 0.0
	var yaw := 0.0
	var camera_yaw := 0.0
	var seated := false
	func is_seated() -> bool: return seated

class ClockFixture extends Node:
	var total_minutes := 10.0
	var elapsed_seconds := 0.0

class ResidentsFixture extends Node:
	var actors: Dictionary = {}
	var state: Dictionary = {"version": 1, "residents": {}}
	var events: Array = []
	func initialize() -> void:
		for i in 20:
			var id := "resident_%d" % i
			actors[id] = true
			state.residents[id] = {"position": [i + 1., 0., 1.], "yaw": 0., "activity": "home", "route_cursor": 0, "slot": 0}
	func get_status() -> Dictionary: return {"pending_routes": 0}
	func snapshot_state() -> Dictionary: return state.duplicate(true)
	func restore_state(value: Dictionary) -> Dictionary:
		events.append("residents")
		state = value.duplicate(true)
		return {"restored": 20, "fallback": 0}

class MissionsFixture extends Node3D:
	var cases: RefCounted
	var state: Dictionary = {"completed_ids": [], "active_id": "", "stage": 0, "score": 0}
	var required: Variant = ["resident_0"]
	var replace_dead := false
	func save_schema() -> Dictionary: return {"case_a": {"reward": 10, "stages": 2}}
	func snapshot_state() -> Dictionary: return state.duplicate(true)
	func preflight_restore(_state: Dictionary) -> bool: return true
	func validate_state(_state: Dictionary, _world := {}) -> String: return ""
	func restore_state(value: Dictionary) -> bool:
		state = value.duplicate(true)
		return true
	func required_contacts(_state: Dictionary, dead: Array) -> Variant:
		return ["resident_1"] if replace_dead and "resident_0" in dead else required

class CombatFixture extends Node:
	const MAX_DEATHS := 100
	var health := 100.0
	var dead: Array = []
	var events: Array = []
	var inventory := {"version": 1, "equipped": "fists", "weapons": {"fists": {"owned": true, "ammo": 0, "reserve": 0}, "pistol": {"owned": true, "ammo": 12, "reserve": 72}}}
	func get_status() -> Dictionary:
		return {"active_count": 0, "knocked_count": 0, "downed": 0., "combo": 0, "reloading": false, "health": health, "weapon": "fists", "ammo": 0, "reserve": 0}
	func equipment_snapshot() -> Dictionary: return inventory.duplicate(true)
	func validate_equipment(_value) -> bool: return true
	func restore_equipment(value: Dictionary) -> void: inventory = value.duplicate(true)
	func death_snapshot() -> Dictionary: return {"version": 1, "dead": dead.duplicate()}
	func dead_ids() -> Array: return dead.duplicate()
	func restore_deaths(value: Dictionary) -> bool:
		events.append("deaths")
		for id in value.dead:
			if not id in dead: dead.append(id)
		return true

class AssistanceFixture extends Node:
	var custody: RefCounted
	var busy := true
	var checkpoint_blocked := false
	var ids: Array = []
	var events: Array = []
	func is_busy() -> bool: return busy
	func blocks_checkpoint() -> bool: return checkpoint_blocked
	func snapshot_state() -> Dictionary: return {"version": 1, "custody_ids": ids.duplicate()}
	func validate_state(_value) -> String: return ""
	func restore_state(value: Dictionary) -> Dictionary:
		events.append("custody")
		for id in value.custody_ids:
			if not id in ids: ids.append(id)
		return {"ok": true, "restored": ids.size()}

class IncidentFixture extends Node:
	var state: Dictionary = {"version": 1, "next_sequence": 2, "incidents": [{"id": "inc_000001"}]}
	var events: Array = []
	var fail_once := false
	func snapshot_state() -> Dictionary: return state.duplicate(true)
	func validate_state(value) -> String:
		return "invalid record list" if not value is Dictionary or not value.get("incidents") is Array or value.get("invalid", false) else ""
	func restore_state(value: Dictionary) -> Dictionary:
		events.append("incidents")
		state = value.duplicate(true)
		if fail_once:
			fail_once = false
			return {"ok": false, "reason": "injected late refusal"}
		return {"ok": true, "restored": state.incidents.size()}
	func blocks_checkpoint() -> bool: return false

class BicycleFixture extends Node:
	var recovering := false
	func blocks_checkpoint() -> bool: return recovering

class LevelFixture extends Node3D:
	var player: Node3D
	var world_time: Node
	var residents: Node
	var missions: Node3D
	var combat: Node
	var police_assistance: Node
	var incidents: Node
	var bicycle: Node
	var progression: Node
	var driving: Node
	var law: Node
	var npcs: Node
	var paused := false
	var _safe_position := Vector3.ZERO
	var visited: Dictionary = {}
	var route_index := 0
	var landmarks: Array = []
	var level_data := {"terrain_extent": {"min": [-100., -20., -100.], "max": [100., 20., 100.]}}

class MemorySave extends "res://scripts/city/city_world_save.gd":
	var fixture_state: Dictionary = {}
	func read_snapshot() -> Dictionary:
		return {"ok": true, "state": fixture_state.duplicate(true), "source": "fixture", "backup": false}
	func safe_player_position(point: Vector3) -> Dictionary: return {"position": point}
	func _put_player(at: Vector3, heading: float) -> void:
		level.player.global_position = at
		level.player.yaw = heading
	func _place_player(state: Dictionary) -> String:
		_put_player(Vector3(state.player.position[0], state.player.position[1], state.player.position[2]), float(state.player.yaw))
		return "saved"

class CaseVersionFixture extends RefCounted:
	const VERSION := 2

class CustodyVersionFixture extends RefCounted:
	const PERSIST_VERSION := 2

class DeathVersionFixture extends CombatFixture:
	const DEATH_VERSION := 2

class CountingSave extends "res://scripts/city/city_world_save.gd":
	var reads: Dictionary = {}
	var fail_temporary_verification := false
	func _read(source: String) -> Dictionary:
		reads[source] = int(reads.get(source, 0)) + 1
		var result := super._read(source)
		if fail_temporary_verification and source == path + ".tmp" and int(reads[source]) == 2:
			return {"ok": false, "reason": "injected verification failure"}
		return result

func _ready() -> void: _run.call_deferred()

func check(value: bool, label: String) -> void:
	passes += int(value)
	failures += int(not value)
	print("[incident_save] %s %s" % ["PASS" if value else "FAIL", label])

func _level() -> LevelFixture:
	var level := LevelFixture.new()
	add_child(level)
	level.player = PlayerFixture.new()
	level.world_time = ClockFixture.new()
	level.residents = ResidentsFixture.new()
	level.missions = MissionsFixture.new()
	level.combat = CombatFixture.new()
	level.police_assistance = AssistanceFixture.new()
	level.incidents = IncidentFixture.new()
	level.bicycle = BicycleFixture.new()
	for child in [level.player, level.world_time, level.residents, level.missions, level.combat, level.police_assistance, level.incidents, level.bicycle]:
		level.add_child(child)
	level.residents.initialize()
	var events: Array = []
	for provider in [level.combat, level.residents, level.police_assistance, level.incidents]:
		provider.events = events
	return level

func _state(level: LevelFixture) -> Dictionary:
	return {"version": 1, "chapter": "pen_lucy", "clock": {"total_minutes": 50., "elapsed_seconds": 3.},
		"player": {"position": [2., 0., 2.], "yaw": 1.}, "residents": level.residents.snapshot_state(),
		"missions": level.missions.snapshot_state(), "walk": {"visited": [], "route_index": 0},
		"deaths": level.combat.death_snapshot(), "police_assistance": level.police_assistance.snapshot_state(),
		"incidents": level.incidents.snapshot_state()}

func _run() -> void:
	var level := _level()
	var provider := MemorySave.new()
	level.add_child(provider)
	provider.level = level
	provider.enabled = true
	var state := _state(level)
	check(provider.validate_snapshot(state).is_empty(), "optional incident section validates through its owner")
	var legacy := state.duplicate(true)
	legacy.erase("incidents")
	check(provider.validate_snapshot(legacy).is_empty(), "old checkpoints without incidents remain valid")
	check(provider.snapshot_state().get("incidents") == level.incidents.snapshot_state(), "snapshot includes incident history")
	var bad := state.duplicate(true)
	bad.incidents.invalid = true
	check(provider.validate_snapshot(bad).begins_with("invalid incidents"), "owner rejects malformed incidents before restore")
	bad = state.duplicate(true)
	bad.incidents.version = 2
	bad.clock = "also corrupt"
	check(provider.validate_snapshot(bad) == "unsupported version", "future incidents protect whole slot before unrelated corruption")
	bad = state.duplicate(true)
	bad.missions.case_engine = {"version": 2}
	bad.clock = "also corrupt"
	check(provider.validate_snapshot(bad) == "unsupported version", "future case engine protects whole slot")
	var incidents: Node = level.incidents
	level.incidents = null
	check(provider.validate_snapshot(state) == "unsupported version" and provider.validate_snapshot(legacy).is_empty(), "absent incident service preserves present section but accepts legacy saves")
	level.incidents = incidents
	check(provider.checkpoint_blocker().is_empty(), "safe autonomous police activity does not block forever")
	level.police_assistance.checkpoint_blocked = true
	check(provider.checkpoint_blocker() == "police response in progress", "phone or custody transition blocks checkpoint")
	level.police_assistance.checkpoint_blocked = false
	level.bicycle.recovering = true
	check(provider.checkpoint_blocker() == "recovering from a bicycle crash" and not provider.load_state().ok, "crash recovery blocks save and load")
	level.bicycle.recovering = false
	level.player.impact_recovery = .5
	check(provider.checkpoint_blocker() == "recovering from an impact" and not provider.load_state().ok, "player impact recovery blocks save and load")
	level.player.impact_recovery = 0.
	bad = state.duplicate(true)
	bad.missions.active_id = "case_a"
	bad.deaths.dead = ["resident_0"]
	check(provider.validate_snapshot(bad) == "case requires deceased contact", "case-required contacts checked against saved deaths")
	level.missions.replace_dead = true
	check(provider.validate_snapshot(bad).is_empty(), "missions owner may choose a living replacement contact")
	level.missions.replace_dead = false
	bad.deaths.dead = []
	level.combat.dead = ["resident_0"]
	check(provider._preflight(bad) == "case requires deceased contact", "preflight includes durable deaths newer than checkpoint")
	level.combat.dead = []
	level.missions.required = "malformed"
	check(provider.validate_snapshot(bad) == "invalid case progress", "malformed required-contact result rejected")
	level.missions.required = ["resident_0"]
	provider.fixture_state = state.duplicate(true)
	level.combat.events.clear()
	check(provider.load_state().ok, "incident checkpoint restores")
	check(level.combat.events == ["deaths", "residents", "custody", "incidents"], "incidents restore after deaths residents and custody")
	provider.fixture_state = legacy.duplicate(true)
	check(provider.load_state().ok and level.incidents.state.incidents.is_empty(), "legacy load clears later-session incident history")
	level.incidents.state = state.incidents.duplicate(true)
	level.world_time.total_minutes = 11.
	var before_residents: Dictionary = level.residents.snapshot_state()
	var before_incidents: Dictionary = level.incidents.snapshot_state()
	provider.fixture_state = state.duplicate(true)
	provider.fixture_state.residents.residents.resident_0.position = [60., 0., 1.]
	provider.fixture_state.incidents.next_sequence = 3
	provider.fixture_state.incidents.incidents.append({"id": "inc_000002"})
	level.incidents.fail_once = true
	var rejected := provider.load_state()
	check(not rejected.ok and rejected.rollback_clean and not rejected.partial, "late incident failure rolls back reversible state cleanly")
	check(level.world_time.total_minutes == 11. and level.residents.snapshot_state() == before_residents and level.incidents.snapshot_state() == before_incidents, "rollback restores clock resident placement and incident records")
	provider.fixture_state.deaths.dead = ["resident_0"]
	provider.fixture_state.police_assistance.custody_ids = ["resident_1"]
	level.incidents.fail_once = true
	rejected = provider.load_state()
	check(not rejected.ok and rejected.partial and not rejected.rollback_clean and provider.get_status().write_blocked, "durable death/custody additions cannot masquerade as clean rollback")
	_slots(level, state)
	_owner_versions(level, state)
	_write_reads(level, state)
	print("[incident_save] %d passed, %d failed" % [passes, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _slots(level: LevelFixture, state: Dictionary) -> void:
	var root_path := ProjectSettings.globalize_path("res://../.work/pacifist-foundation/incident-save-tests")
	DirAccess.make_dir_recursive_absolute(root_path)
	var provider := CountingSave.new()
	level.add_child(provider)
	for section in ["incidents", "case_engine", "police_assistance", "deaths"]:
		for slot in ["", ".bak", ".tmp"]:
			var path := root_path.path_join("future-" + section + "-" + str(slot.length()) + ".json")
			provider.setup(level, path)
			provider._write_blocked = false
			for suffix in ["", ".bak", ".tmp"]:
				if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
			var future := state.duplicate(true)
			if section == "incidents": future.incidents.version = 2
			elif section == "case_engine": future.missions.case_engine = {"version": 2}
			else: future[section].version = 2
			var primary := FileAccess.open(path, FileAccess.WRITE)
			primary.store_string(JSON.stringify(state))
			primary.close()
			var file := FileAccess.open(path + slot, FileAccess.WRITE)
			var original := JSON.stringify(future)
			file.store_string(original)
			file.close()
			var result := provider.read_snapshot()
			check(not result.ok and result.reason == "unsupported version" and provider.write_snapshot(state) == ERR_UNAVAILABLE and FileAccess.get_file_as_string(path + slot) == original, "future %s in slot '%s' prevents fallback and overwrite" % [section, slot])
			provider._write_blocked = false
			provider.reads.clear()
			check(provider.write_snapshot(state) == ERR_UNAVAILABLE and provider._write_blocked and provider.reads == {path: 1, path + ".bak": 1, path + ".tmp": 1} and FileAccess.get_file_as_string(path + slot) == original, "direct write checks each slot once and preserves future %s in '%s'" % [section, slot])

func _owner_versions(level: LevelFixture, state: Dictionary) -> void:
	var provider := Save.new()
	level.add_child(provider)
	provider.level = level
	var original_combat := level.combat
	var newer_combat := DeathVersionFixture.new()
	level.add_child(newer_combat)
	level.combat = newer_combat
	level.missions.cases = CaseVersionFixture.new()
	level.police_assistance.custody = CustodyVersionFixture.new()
	for section in ["case_engine", "police_assistance", "deaths"]:
		var current := state.duplicate(true)
		if section == "case_engine": current.missions.case_engine = {"version": 2}
		else: current[section].version = 2
		check(provider.validate_snapshot(current).is_empty(), "%s accepts its owner's declared version 2" % section)
		if section == "case_engine": current.missions.case_engine.version = 3
		else: current[section].version = 3
		current.clock = "also corrupt"
		check(provider.validate_snapshot(current) == "unsupported version", "%s owner version + 1 wins over unrelated corruption" % section)
	level.combat = original_combat
	level.missions.cases = null
	level.police_assistance.custody = null
	newer_combat.queue_free()

func _write_reads(level: LevelFixture, state: Dictionary) -> void:
	var root_path := ProjectSettings.globalize_path("res://../.work/pacifist-foundation/incident-save-tests")
	var original := JSON.stringify(state)
	var next := state.duplicate(true)
	next.clock.total_minutes += 1.
	# JSON parsing changes integer Variants to floats, which makes nested
	# Dictionary equality differ from the in-memory fixture. Check every byte
	# of the requested serialized payload at the final path instead.
	var expected_contents := JSON.stringify(next)
	var scenarios := {
		"rotation": {"": original, ".bak": original},
		"rejected-primary": {"": "broken-primary", ".bak": original},
		"rejected-backup": {"": original, ".bak": "broken-backup"},
		"rejected-temporary": {"": original, ".tmp": "broken-temporary"},
		"sole-temporary": {".tmp": original},
		"verification-failure": {"": original, ".bak": original},
		"no-valid-source": {"": "broken-only-source"},
	}
	for name in scenarios:
		var provider := CountingSave.new()
		level.add_child(provider)
		var slot_path := root_path.path_join("reads-" + str(name) + ".json")
		provider.setup(level, slot_path)
		for suffix in ["", ".bak", ".tmp"]:
			if FileAccess.file_exists(slot_path + suffix): DirAccess.remove_absolute(slot_path + suffix)
		for suffix in scenarios[name]:
			var file := FileAccess.open(slot_path + suffix, FileAccess.WRITE)
			file.store_string(scenarios[name][suffix])
			file.close()
		provider.fail_temporary_verification = name == "verification-failure"
		var result := provider.write_snapshot(next)
		var blocked: bool = name == "no-valid-source"
		check(provider.reads == {slot_path: 1, slot_path + ".bak": 1, slot_path + ".tmp": 1 if blocked else 2}, "%s reads each source once and verifies only a newly written temporary" % name)
		if blocked:
			check(result == ERR_UNAVAILABLE and provider._write_blocked and FileAccess.get_file_as_string(slot_path) == scenarios[name][""], "no valid source blocks writes and preserves rejected bytes")
		elif provider.fail_temporary_verification:
			check(result == ERR_FILE_CANT_WRITE and FileAccess.get_file_as_string(slot_path) == original and FileAccess.get_file_as_string(slot_path + ".bak") == original, "failed temporary verification leaves primary and backup unchanged")
		else:
			check(result == OK and FileAccess.get_file_as_string(slot_path) == expected_contents and not FileAccess.file_exists(slot_path + ".tmp"), "%s publishes the requested checkpoint" % name)
			check(FileAccess.get_file_as_string(slot_path + ".bak") == original, "%s keeps the preceding valid checkpoint as backup" % name)
			if str(name).begins_with("rejected-"):
				var rejected_suffix: String = {"rejected-primary": "", "rejected-backup": ".bak", "rejected-temporary": ".tmp"}[name]
				check(provider._preserved_files.size() == 1 and FileAccess.get_file_as_string(provider._preserved_files[0]) == scenarios[name][rejected_suffix], "%s preserves rejected source bytes before replacement" % name)
