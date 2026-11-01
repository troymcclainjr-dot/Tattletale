extends SceneTree
## Independent, pure save-boundary regression. No world, filesystem or engine job
## is launched by the authoring worker. Root runs this through the locked runner.
const Save := preload("res://scripts/city/city_world_save.gd")

class AuditMissions extends Node:
	var received_context: Dictionary = {}
	func save_schema() -> Dictionary:
		return {"petals_report": {"reward": 100, "stages": 2, "kind": "story"},
			"errand_delivery": {"reward": 0, "stages": 2, "kind": "errand"}}
	func validate_state(section: Dictionary, whole_snapshot: Dictionary = {}) -> String:
		received_context = whole_snapshot
		if "errand_delivery" in section.completed_ids:
			return "repeatable errand in completed cases"
		if str(section.active_id) == "petals_report":
			if not whole_snapshot.has("progression") or not whole_snapshot.has("deaths"):
				return "missing whole checkpoint context"
			if str(whole_snapshot.progression.get("choices", {}).get("petals_call", "")) != "report":
				return "saved branch mismatch"
		return ""
	func case_steps(_id: String) -> Array:
		return [{"target": "@police"}, {"target": "@carrier"}]

class AuditProgression extends Node:
	const VERSION := 2
	func validate_state(_state: Dictionary) -> String:
		return ""

class AuditCombat extends Node:
	func validate_equipment(_state: Dictionary) -> bool:
		return true
	func equipment_snapshot() -> Dictionary:
		return {"version": 1}

class AuditResidents extends Node:
	const STATE_VERSION := 1
	var actors: Dictionary = {}

class AuditLevel extends Node3D:
	var missions: Node
	var progression: Node
	var combat: Node
	var residents: Node
	var driving: Node
	var npcs: Node
	var landmarks: Array = []
	var level_data := {"terrain_extent": {"min": [-100, -100, -100], "max": [100, 100, 100]}}

var failures := 0
var passes := 0

func check(ok: bool, label: String) -> void:
	print("[save_story_audit] %s %s" % ["PASS" if ok else "FAIL", label])
	passes += int(ok)
	failures += int(not ok)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var level := AuditLevel.new()
	root.add_child(level)
	level.missions = AuditMissions.new()
	level.progression = AuditProgression.new()
	level.combat = AuditCombat.new()
	level.residents = AuditResidents.new()
	for manager in [level.missions, level.progression, level.combat, level.residents]:
		level.add_child(manager)
	var residents: Dictionary = {}
	for index in 20:
		var id := "daily_fixture_%d" % index
		level.residents.actors[id] = null
		residents[id] = {"position": [index, 0, 0], "yaw": 0, "activity": "home", "route_cursor": 0, "slot": 0}
	var provider := Save.new()
	level.add_child(provider)
	provider.level = level # Pure validators only; no checkpoint path is opened.
	var state := {"version": 3, "chapter": "pen_lucy", "clock": {"total_minutes": 540, "elapsed_seconds": 100},
		"player": {"position": [0, 0, 0], "yaw": 0}, "residents": {"version": 1, "residents": residents},
		"missions": {"active_id": "petals_report", "stage": 1, "completed_ids": [], "score": 0},
		"walk": {"visited": [], "route_index": 0}, "deaths": {"version": 1, "dead": []},
		"equipment": {"health": 100, "weapon": "fists", "ammo": 0, "reserve": 0},
		"inventory": {"version": 1, "equipped": "fists", "weapons": {"fists": {"ammo": 0, "reserve": 0}}},
		"progression": {"version": 2, "choices": {"petals_call": "report"}}}
	var valid_reason: String = provider.validate_snapshot(state)
	check(valid_reason.is_empty(), "valid saved branch is checked using its own checkpoint context: " + valid_reason)
	check(level.missions.received_context == state, "mission validator receives entire saved progression/clock/death context")
	var wrong_branch: Dictionary = state.duplicate(true)
	wrong_branch.progression.choices.petals_call = "protect"
	check(provider.validate_snapshot(wrong_branch) == "invalid cases: saved branch mismatch",
		"wrong saved branch fails static validation before a load/preflight can select it")
	var repeatable: Dictionary = state.duplicate(true)
	repeatable.missions = {"active_id": "errand_delivery", "stage": 1, "completed_ids": [], "score": 0}
	check(provider.validate_snapshot(repeatable).is_empty(), "active repeatable errand stage needs no fake completion or score")
	repeatable.missions.completed_ids = ["errand_delivery"]
	repeatable.missions.active_id = ""
	repeatable.missions.stage = 0
	check(provider.validate_snapshot(repeatable).begins_with("invalid cases:"), "repeatable errand may not enter completed IDs")
	for version in [1, 2, 3]:
		var legacy: Dictionary = state.duplicate(true)
		legacy.version = version
		legacy.missions = {"active_id": "", "stage": 0, "completed_ids": [], "score": 0}
		if version < 3:
			legacy.erase("inventory")
			legacy.erase("progression")
		if version == 1:
			legacy.erase("equipment")
			legacy.erase("deaths")
		check(provider.validate_snapshot(legacy).is_empty(), "context handoff keeps schema%d structural compatibility" % version)
	var rejected: Dictionary = provider._refuse({"source": "checkpoint"}, 4, "case unavailable", false)
	check(rejected.get("partial", false) and not rejected.get("rollback_clean", true),
		"inexact rollback reports partial application")
	check(not str(rejected.reason).contains("without applying world state"), "inexact rollback does not claim world state stayed unchanged")
	var clean: Dictionary = provider._refuse({"source": "checkpoint"}, 4, "case unavailable", true)
	check(not clean.get("partial", true) and clean.get("rollback_clean", false), "exact rollback remains an atomic refusal")
	print("[save_story_audit] %d passed; %d failed" % [passes, failures])
	quit(0 if failures == 0 else 1)
