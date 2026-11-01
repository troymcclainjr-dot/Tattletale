extends SceneTree

class LedgerMissions extends CityMissions:
	func nearby_offer() -> Dictionary:
		return {}
	func _available_offers() -> Array[Dictionary]:
		return []
	func _can_interact(_target: Vector3) -> bool:
		return false

class Contacts extends Node3D:
	var actors: Dictionary = {}
	func get_actor(id: String) -> Node:
		return actors.get(id)
	func actor_position(_id: String) -> Vector3:
		return Vector3.ZERO

class Deaths extends Node:
	var ids: Dictionary = {}
	func is_actor_dead(id: String) -> bool:
		return ids.has(id)

class LedgerWorld extends Node3D:
	var combat: Node
	var missions: Node

var failures := 0
var _finished := false
func _initialize() -> void:
	call_deferred("_watchdog")
	call_deferred("_run")

func _watchdog() -> void:
	await create_timer(20.0, true, false, true).timeout
	if not _finished:
		push_error("[case_ledger] FAIL fixture did not finish within 20 seconds")
		quit(1)

func _check(condition: bool, label: String) -> void:
	if condition:
		print("[case_ledger] PASS " + label)
	else:
		failures += 1
		push_error("[case_ledger] FAIL " + label)

func _case(missions: Node, id: String) -> Dictionary:
	for entry in missions.get_status().cases:
		if entry.id == id:
			return entry
	return {}

func _run() -> void:
	var world := LedgerWorld.new()
	root.add_child(world)
	var deaths := Deaths.new()
	world.add_child(deaths)
	world.combat = deaths
	var contacts := Contacts.new()
	world.add_child(contacts)
	for id in ["resident", "lookout", "officer", "gardener", "organizer", "caretaker", "ambient_mailman"]:
		var actor := Node3D.new()
		contacts.add_child(actor)
		contacts.actors[id] = actor
	var missions := LedgerMissions.new()
	world.add_child(missions)
	missions.setup(world, contacts)
	world.missions = missions
	_check(_case(missions, "lost_satchel").state == "available" and _case(missions, "parcel_report").state == "locked", "prerequisite is shown without inventing an accepted history")
	deaths.ids["resident"] = true
	_check(_case(missions, "lost_satchel").state == "unavailable" and "has died" in str(_case(missions, "lost_satchel").reason), "persistent death ledger works even before actor metadata is applied")
	missions.completed_ids["lost_satchel"] = true
	missions.score = 100
	_check(_case(missions, "lost_satchel").state == "completed", "completion survives later contact death")
	var saved := missions.snapshot_state()
	var restored := LedgerMissions.new()
	world.add_child(restored)
	restored.setup(world, contacts)
	restored.restore_state(saved)
	_check(_case(restored, "lost_satchel").state == "completed" and _case(restored, "parcel_report").state == "unavailable", "existing mission snapshot plus restored death IDs derives same ledger")
	deaths.ids.clear()
	contacts.actors.erase("officer")
	_check("not currently present" in str(_case(missions, "dumping").reason) and not "has died" in str(_case(missions, "dumping").reason), "missing actor is distinguished from confirmed death")
	contacts.actors["officer"] = contacts.get_child(2)
	missions.active_id = "parcel_report"
	missions.stage = 3
	missions._steps = missions.case_steps("parcel_report")
	deaths.ids["resident"] = true
	deaths.ids["lookout"] = true
	_check(_case(missions, "parcel_report").state == "active", "active case ignores deaths of contacts whose steps are already complete")
	deaths.ids["officer"] = true
	_check(_case(missions, "parcel_report").state == "unavailable", "remaining contact death is explained")
	var unchanged := missions.snapshot_state()
	for ignored in 4:
		missions.get_status()
	_check(missions.snapshot_state() == unchanged and missions.score == 100, "reading ledger does not mutate checkpoint, rewards, or progress")
	_check(not missions.commit_dialogue_action({"kind": "case_step", "id": "dumping", "stage": 3}), "stale dialogue hook remains rejected")
	var settings_script: Script = load("res://scripts/city/city_settings.gd")
	if settings_script == null or not settings_script.can_instantiate():
		_check(false, "Settings script loads after autoload registration")
		_finished = true
		quit(1)
		return
	var settings = settings_script.new()
	world.add_child(settings)
	settings.level = world
	settings._show_cases()
	_check("Lost satchel — Completed" in settings._case_text.text and "Required contact Officer has died." in settings._case_text.text, "Settings Cases modal renders truthful current ledger")
	settings._cases.hide()
	world.free()
	_finished = true
	quit(1 if failures else 0)
