extends Node
## Production level callbacks with provider spies. Real knockdown/recovery is
## covered by city_pacifist_combat_smoke; this fixture checks only routing.
class LevelProbe:
	extends "res://scripts/city/pen_lucy_level.gd"
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func _input(_event: InputEvent) -> void: pass
	func _unhandled_input(_event: InputEvent) -> void: pass
	func _notification(_what: int) -> void: pass
	func _exit_tree() -> void: pass

class CombatProbe:
	extends Node3D
	signal player_offense(kind: String, at: Vector3, id: String)
	var calls: Array[Dictionary] = []
	var forbidden_calls := 0
	var health := 100.0
	func knockdown_from_bicycle(target, speed: float, impulse := Vector3.ZERO, context := {}) -> Dictionary:
		calls.append({"target": target, "speed": speed, "impulse": impulse, "context": context.duplicate(true)})
		return {"ok": true, "outcome": "fixture_only"}
	func _fighter_for(_actor, _index: int, _mode: String) -> Dictionary:
		forbidden_calls += 1
		return {}
	func _panic_actor(_actor, _origin: Vector3, _mode: String) -> bool:
		forbidden_calls += 1
		return false
	func _damage_target(_body, _damage: float, _source: String, _origin := Vector3.INF, _by_player := true) -> bool:
		forbidden_calls += 1
		return false
	func _hurt_player(_amount: float) -> bool:
		forbidden_calls += 1
		return false
	func hit_actor(_actor, _damage: float, _origin: Vector3, _firearm := false) -> bool:
		forbidden_calls += 1
		return false
	func hit_crowd(_index: int, _damage: float, _origin: Vector3, _firearm := false) -> bool:
		forbidden_calls += 1
		return false

class ProgressProbe:
	extends Node
	var money := 321
	var reputation := {"snitch": 14, "gangsta": 27}
	var offense_calls := 0
	func on_offense(_kind: String, _at: Vector3, _id: String) -> void:
		offense_calls += 1
		money += 1

class PhoneProbe:
	extends Node3D
	var message := ""
	func set_report_status(value: String) -> void: message = value

class PlayerProbe:
	extends CharacterBody3D
	var phone: Node3D

class DispatchProbe:
	extends Node
	var locations: Array[Vector3] = []
	func request_help(at: Vector3) -> Dictionary:
		locations.append(at)
		return {"ok": false, "message": "Fixture: no officer available."}

class IncidentProbe:
	extends Node3D
	var locations: Array[Vector3] = []
	func report_from_phone(at: Vector3) -> Dictionary:
		locations.append(at)
		return {"ok": true, "message": "Fixture: incident corroborated."}

var failures := 0
var offense_signals := 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("[bicycle_contact_integration] %s %s" % ["PASS" if ok else "FAIL", label])

func _run() -> void:
	var level := LevelProbe.new()
	add_child(level)
	var combat := CombatProbe.new()
	level.add_child(combat)
	level.combat = combat
	level.progression = ProgressProbe.new()
	level.add_child(level.progression)
	combat.player_offense.connect(func(_kind: String, _at: Vector3, _id: String): offense_signals += 1)
	combat.player_offense.connect(level.progression.on_offense)
	var tracks: Dictionary = level.progression.reputation.duplicate(true)
	var actor := Node3D.new()
	level.add_child(actor)
	var contact := {"collider": actor, "relative_speed": 3.25, "speed": 9.0,
		"impulse": Vector3(12, 0, -3), "direction": Vector3.FORWARD, "position": Vector3(4, 0, 7),
		"crowd_index": 17, "actor_id": "crowd_17", "source": "bicycle", "harmless": true, "body_damage": 0.0}
	level._on_bicycle_contact(contact)
	check(combat.calls.size() == 1 and combat.calls[0].target == actor and combat.calls[0].speed == 3.25
		and combat.calls[0].impulse == contact.impulse and combat.calls[0].context == contact,
		"relative speed, collider, explicit impulse and complete original context forwarded once")
	level._on_bicycle_contact({"collider": actor, "speed": 2.0, "direction": Vector3.FORWARD})
	check(combat.calls.size() == 2 and combat.calls.back().speed == 2.0 and combat.calls.back().impulse == Vector3.FORWARD * 2.0,
		"legacy payload falls back to speed and direction times speed")
	level._on_bicycle_contact({"collider": actor, "relative_speed": 1.5, "speed": 8.0, "direction": Vector3.RIGHT})
	check(combat.calls.size() == 3 and combat.calls.back().speed == 1.5 and combat.calls.back().impulse == Vector3.RIGHT * 1.5,
		"fallback impulse also uses relative contact speed")
	level._on_bicycle_contact({"collider": actor, "speed": .1})
	level._on_bicycle_contact({"collider": actor, "speed": .1})
	check(combat.calls.size() == 5 and combat.calls.back().impulse == Vector3.ZERO,
		"small and repeated contacts delegate thresholds and deduplication without duplicate routing")
	level._on_bicycle_contact({})
	check(combat.calls.size() == 6 and combat.calls.back().target == null and combat.calls.back().speed == 0.0,
		"missing target is forwarded to the authoritative eligibility gate")
	level.combat = null
	level._on_bicycle_contact(contact)
	level.combat = combat
	check(combat.calls.size() == 6, "unavailable combat provider is a no-op")
	check(combat.forbidden_calls == 0 and combat.health == 100.0, "root bridge calls no fighter, panic or damage API")
	check(offense_signals == 0 and level.progression.offense_calls == 0 and level.progression.money == 321 and level.progression.reputation == tracks,
		"root contact bridge never emits player offense or changes money/alignment")
	level.player = PlayerProbe.new()
	level.add_child(level.player)
	level.player.phone = PhoneProbe.new()
	level.player.add_child(level.player.phone)
	level.police_assistance = DispatchProbe.new()
	level.add_child(level.police_assistance)
	var caller := Vector3(142.25, 7.5, -93.75)
	level._request_police_help(caller)
	check(level.police_assistance.locations == [caller] and level.player.phone.message == "Fixture: no officer available.",
		"without incident service phone preserves legacy dispatch fallback and honest result")
	level.incidents = IncidentProbe.new()
	level.add_child(level.incidents)
	level._request_police_help(caller)
	check(level.incidents.locations == [caller] and level.police_assistance.locations.size() == 1
		and level.player.phone.message == "Fixture: incident corroborated.", "installed incident service receives exact phone coordinates once")
	level._on_incident_report_status({"phone": false, "text": "NPC-only status"})
	check(level.player.phone.message == "Fixture: incident corroborated.", "NPC-only status cannot overwrite phone report")
	level._on_incident_report_status({"phone": true, "text": "Officer arrived"})
	check(level.player.phone.message == "Officer arrived", "subscribed status reaches phone through actual level callback")
	level.queue_free()
	await get_tree().process_frame
	print("[bicycle_contact_integration] failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
