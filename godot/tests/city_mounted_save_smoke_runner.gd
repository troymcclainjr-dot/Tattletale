extends Node
## Provider-contract fixtures for mounted-bicycle checkpoints and the queued save
## request (.work/five-priorities-20261101/save-contract.md r2). Doubles only: no
## city model, renderer or user slot. The bicycle double publishes the verdicts and
## facts of bicycle-save-contract.md section 3, so the save side is judged on what a
## real bicycle reports; the actual bicycle is city_mounted_save_city_runner.gd.
## Every file lives under .work/five-priorities-20261101/mounted-save-tests/.
## Run: --headless --script res://tests/city_mounted_save_smoke.gd
const Save := preload("res://scripts/city/city_world_save.gd")
const Mounted := preload("res://scripts/city/city_bicycle_checkpoint.gd")
const STEP := 1.0 / 60.0
var passes := 0
var failures := 0
var root_path := ""
## Restore order shared by every double that applies state.
var events: Array = []
## pending_save_resolved payloads of the current world.
var resolved: Array = []

class PlayerDouble extends CharacterBody3D:
	var impact_recovery := 0.0
	var yaw := 0.0
	var camera_yaw := 0.0
	var seated_vehicle: Node3D
	func is_seated() -> bool: return seated_vehicle != null

class ClockDouble extends Node:
	var total_minutes := 600.0
	var elapsed_seconds := 0.0

class ResidentsDouble extends Node:
	var actors: Dictionary = {}
	var definitions: Array = []
	var events: Array
	func initialize(ids: Array) -> void:
		for index in ids.size():
			var actor := Node3D.new()
			add_child(actor)
			actor.global_position = Vector3(-60.0 + index * 1.5, 0.0, -60.0)
			actors[ids[index]] = actor
			definitions.append({"id": ids[index]})
	func get_status() -> Dictionary: return {"pending_routes": 0}
	func snapshot_state() -> Dictionary:
		var residents := {}
		for id in actors:
			var at: Vector3 = actors[id].global_position
			residents[id] = {"position": [at.x, at.y, at.z], "yaw": 0.0, "activity": "home", "route_cursor": 0, "slot": 0}
		return {"version": 1, "residents": residents}
	func restore_state(value: Dictionary) -> Dictionary:
		events.append("residents")
		for id in value.residents:
			var at: Array = value.residents[id].position
			actors[id].global_position = Vector3(float(at[0]), float(at[1]), float(at[2]))
		return {"ok": true, "restored": value.residents.size(), "fallback": 0}

class MissionsDouble extends Node3D:
	## An active data case with recorded evidence and a completed, rewarded case.
	var state: Dictionary = {"completed_ids": ["case_a"], "active_id": "case_b", "stage": 1, "score": 10,
		"case_engine": {"version": 1, "active": {"id": "case_b", "evidence": ["photo_7", "statement_2"]}, "rewarded": ["case_a"]}}
	var restores := 0
	var events: Array
	func save_schema() -> Dictionary: return {"case_a": {"reward": 10, "stages": 2}, "case_b": {"reward": 15, "stages": 3}}
	func snapshot_state() -> Dictionary: return state.duplicate(true)
	func preflight_restore(_value: Dictionary) -> bool: return true
	func validate_state(_value, _snapshot := {}) -> String: return ""
	func required_contacts(_value: Dictionary, _dead: Array) -> Variant: return []
	func restore_state(value: Dictionary) -> bool:
		restores += 1
		events.append("missions")
		state = value.duplicate(true)
		return true

class CombatDouble extends Node:
	const MAX_DEATHS := 100
	var health := 100.0
	var downed := 0.0
	var dead: Array = []
	var events: Array
	var inventory := {"version": 1, "equipped": "fists", "weapons": {"fists": {"owned": true, "ammo": 0, "reserve": 0}, "pistol": {"owned": true, "ammo": 12, "reserve": 72}}}
	func get_status() -> Dictionary:
		return {"active_count": 0, "knocked_count": 0, "downed": downed, "combo": 0, "reloading": false, "health": health, "weapon": "fists", "ammo": 0, "reserve": 0}
	func equipment_snapshot() -> Dictionary: return inventory.duplicate(true)
	func validate_equipment(_value) -> bool: return true
	func restore_equipment(value: Dictionary) -> void: inventory = value.duplicate(true)
	func death_snapshot() -> Dictionary: return {"version": 1, "dead": dead.duplicate()}
	func dead_ids() -> Array: return dead.duplicate()
	func restore_deaths(value: Dictionary) -> bool:
		events.append("deaths")
		for id in value.dead:
			if not id in dead:
				dead.append(id)
		return true

class ProgressionDouble extends Node:
	const VERSION := 2
	var state: Dictionary = {"version": 2, "money": 120}
	var restores := 0
	var _session_loaded := true
	func snapshot_state() -> Dictionary: return state.duplicate(true)
	func validate_state(_value) -> String: return ""
	func restore_state(value) -> bool:
		restores += 1
		state = value.duplicate(true)
		return true
	func reconcile_cases(_ids) -> void: pass
	func setup(_level) -> void: state = {"version": 2, "money": 0}
	func migrate_legacy(_ids) -> void: pass

class AssistanceDouble extends Node:
	var checkpoint_blocked := false
	var ids: Array = []
	## Anything that would interrupt a response. The save must never call these.
	var interruptions: Array = []
	var events: Array
	func blocks_checkpoint() -> bool: return checkpoint_blocked
	func snapshot_state() -> Dictionary: return {"version": 1, "custody_ids": ids.duplicate()}
	func validate_state(_value) -> String: return ""
	func restore_state(value: Dictionary) -> Dictionary:
		events.append("custody")
		ids = value.custody_ids.duplicate()
		return {"ok": true, "restored": ids.size()}
	func reset_state() -> void: interruptions.append("reset_state")
	func cancel_response(_reason := "") -> void: interruptions.append("cancel_response")

class IncidentDouble extends Node:
	var state: Dictionary = {"version": 1, "next_sequence": 2, "incidents": [{"id": "inc_000001"}]}
	var fail_once := false
	var events: Array
	func snapshot_state() -> Dictionary: return state.duplicate(true)
	func validate_state(value) -> String: return "" if value is Dictionary and value.get("incidents") is Array else "invalid record list"
	func blocks_checkpoint() -> bool: return false
	func restore_state(value: Dictionary) -> Dictionary:
		events.append("incidents")
		state = value.duplicate(true)
		if fail_once:
			fail_once = false
			return {"ok": false, "reason": "injected late refusal"}
		return {"ok": true, "restored": state.incidents.size()}

class DrivingDouble extends Node:
	const PERSIST_VERSION := 1
	var active := false
	var applied: Dictionary = {"version": 1, "sequence": 0, "vehicles": []}
	func get_status() -> Dictionary: return {"active": active}
	func snapshot_state() -> Dictionary: return applied.duplicate(true)
	func validate_state(value) -> String: return "" if value is Dictionary and value.get("vehicles") is Array else "fixture schema"
	func preflight_state(_value) -> Dictionary: return {"ok": true, "reason": "", "fallbacks": []}
	func restore_state(value) -> Dictionary:
		applied = value.duplicate(true)
		return {"ok": true, "restored": 0, "fallbacks": []}
	func reset_persistent_state() -> Variant:
		applied = {"version": 1, "sequence": 0, "vehicles": []}
		return null

## bicycle-save-contract.md section 2-3 as published: verdict order and reason
## strings, the facts dictionary and an atomic restore_pose (false changes nothing).
class BicycleDouble extends Node3D:
	const SAVE_STILL_SPEED := 0.05
	var level: Node3D
	var active := false
	var crashed := false
	var settling := false
	var speed := 0.0
	var planar_speed := 0.0
	var grounded := true
	var airborne := false
	var hull_reason := ""
	var pose_reason := ""
	var refuse_restore := ""
	## Forces save_blocker() (e.g. "" while the facts say otherwise).
	var verdict: Variant = null
	## "" | "unseated" (claims ok, seats nobody) | "offset" (seats 0.5 m off the pose)
	var lie := ""
	var yaw := 0.0
	var calls: Array = []
	var events: Array
	func blocks_checkpoint() -> bool: return crashed
	func save_blocker() -> String:
		calls.append("save_blocker")
		if verdict != null:
			return str(verdict)
		if not active:
			return "your bicycle is still settling" if settling else ""
		if crashed:
			return "recovering from a bicycle crash"
		if airborne or not grounded:
			return "land the bicycle before saving"
		if absf(speed) > SAVE_STILL_SPEED or planar_speed > SAVE_STILL_SPEED:
			return "stop the bicycle before saving"
		return hull_reason
	func persistence_state() -> Dictionary:
		return {"mounted": active, "crashed": crashed, "settling": settling, "fallen": false, "grounded": grounded,
			"airborne": airborne, "steady": true, "hull_clear": hull_reason.is_empty(), "supported": grounded,
			"speed": speed, "planar_speed": planar_speed, "position": global_position, "yaw": yaw,
			"parked_position": global_position, "blocker": save_blocker()}
	func pose_blocker(_position: Vector3, _heading: float) -> String:
		calls.append("pose_blocker")
		return pose_reason
	func restore_pose(position: Vector3, heading: float, mounted: bool, fallen := false) -> Dictionary:
		calls.append("restore_pose")
		events.append("bicycle")
		if not refuse_restore.is_empty():
			return {"ok": false, "reason": refuse_restore, "mounted": active, "position": global_position, "yaw": yaw, "fallen": false}
		global_position = position + (Vector3(0.5, 0.0, 0.0) if lie == "offset" else Vector3.ZERO)
		yaw = heading
		speed = 0.0
		planar_speed = 0.0
		airborne = false
		grounded = true
		if mounted and lie != "unseated":
			active = true
			level.player.seated_vehicle = self
			level.player.global_position = global_position
			level.player.yaw = heading
		return {"ok": true, "reason": "", "mounted": mounted, "position": global_position, "yaw": yaw, "fallen": fallen}
	func recovery_exit_at(at: Vector3, heading: float) -> bool:
		calls.append("recovery_exit_at")
		if not active:
			return false
		active = false
		level.player.seated_vehicle = null
		level.player.global_position = at
		level.player.yaw = heading
		return true
	func park_beside_explorer() -> bool:
		calls.append("park_beside_explorer")
		events.append("park")
		global_position = level.player.global_position + Vector3(0.0, 0.0, 2.5)
		yaw = 0.0
		return true
	## Fixture arrangement standing in for a real mount / dismount.
	func mount_here() -> void:
		active = true
		level.player.seated_vehicle = self
		level.player.global_position = global_position
		level.player.yaw = yaw
	func get_off(at: Vector3) -> void:
		active = false
		level.player.seated_vehicle = null
		level.player.global_position = at
	func count(method: String) -> int:
		return calls.count(method)
	func mutations() -> int:
		return count("restore_pose") + count("recovery_exit_at") + count("park_beside_explorer")

## A bicycle from a build without persistence hooks.
class HooklessBicycle extends Node3D:
	func blocks_checkpoint() -> bool: return false

class LevelDouble extends Node3D:
	var player: CharacterBody3D
	var world_time: Node
	var residents: Node
	var missions: Node3D
	var combat: Node
	var progression: Node
	var police_assistance: Node
	var incidents: Node
	var driving: Node
	var bicycle: Node3D
	var paused := false
	var _safe_position := Vector3.ZERO
	var visited: Dictionary = {}
	var route_index := 0
	var landmarks: Array = []
	var level_data := {"terrain_extent": {"min": [-100.0, -20.0, -100.0], "max": [100.0, 20.0, 100.0]}}

## The real provider over flat fixture ground (y = 0), counting slot access.
class FixtureSave extends "res://scripts/city/city_world_save.gd":
	var reads := 0
	var writes := 0
	## Occupied standing spots (0.6 m): people, props or walls the ground test sees.
	var blocked_spots: Array = []
	func _read(source: String) -> Dictionary:
		reads += 1
		return super._read(source)
	func write_snapshot(state: Dictionary) -> Error:
		writes += 1
		return super.write_snapshot(state)
	func safe_player_position(point: Vector3) -> Dictionary:
		if not _in_bounds(point) or absf(point.y) > 0.35:
			return {}
		for spot in blocked_spots:
			if Vector2(point.x - spot.x, point.z - spot.z).length() < 0.6:
				return {}
		return {"position": Vector3(point.x, 0.02, point.z)}
	func _put_player(at: Vector3, heading: float) -> void:
		level.player.global_position = at
		level.player.yaw = heading
		level._safe_position = at

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> bool:
	print("[mounted_save] %s %s" % ["PASS" if ok else "FAIL", label])
	passes += int(ok)
	failures += int(not ok)
	return ok

func _run() -> void:
	root_path = ProjectSettings.globalize_path("res://../.work/five-priorities-20261101/mounted-save-tests")
	DirAccess.make_dir_recursive_absolute(root_path)
	_schema_and_validation()
	await _save_gating()
	_queue_coalescing()
	_queue_autosave_and_pause()
	_failure_backoff()
	_cancel_exit_restart()
	_mounted_restore()
	_restore_fallbacks()
	_legacy_and_disk()
	print("[mounted_save] %d passed, %d failed" % [passes, failures])
	get_tree().quit(1 if failures else 0)

# ------------------------------------------------------------------ fixtures

func _world(label: String) -> Dictionary:
	var level := LevelDouble.new()
	add_child(level)
	level.player = PlayerDouble.new()
	level.world_time = ClockDouble.new()
	level.residents = ResidentsDouble.new()
	level.missions = MissionsDouble.new()
	level.combat = CombatDouble.new()
	level.progression = ProgressionDouble.new()
	level.police_assistance = AssistanceDouble.new()
	level.incidents = IncidentDouble.new()
	level.driving = DrivingDouble.new()
	level.bicycle = BicycleDouble.new()
	for child in [level.player, level.world_time, level.residents, level.missions, level.combat, level.progression,
		level.police_assistance, level.incidents, level.driving, level.bicycle]:
		level.add_child(child)
	var ids: Array = Save.Residents.LEGACY_RESIDENT_IDS.duplicate()
	for index in 20:
		ids.append("fixture_resident_%02d" % index)
	level.residents.initialize(ids)
	events.clear()
	resolved.clear()
	for target in [level.residents, level.missions, level.combat, level.police_assistance, level.incidents, level.bicycle]:
		target.events = events
	level.bicycle.level = level
	level.bicycle.global_position = Vector3(10.0, 0.0, 10.0)
	level.bicycle.yaw = 0.5
	level.player.global_position = Vector3(12.0, 0.0, 7.0)
	var file := root_path.path_join(label + ".json")
	_cleanup(file)
	var provider := FixtureSave.new()
	level.add_child(provider)
	provider.setup(level, file)
	provider.pending_save_resolved.connect(func(result: Dictionary): resolved.append(result))
	return {"level": level, "save": provider, "bike": level.bicycle, "path": file}

func _ticks(provider: Node, seconds: float, step: float) -> void:
	for index in int(roundf(seconds / step)):
		provider.tick(step)

## Ticks until `done` holds; the number of ticks taken, or -1.
func _ticks_until(provider: Node, done: Callable, seconds: float, step: float) -> int:
	for index in int(roundf(seconds / step)):
		provider.tick(step)
		if done.call():
			return index + 1
	return -1

func _expect_blocked(provider: Node, file: String, reason: String, label: String) -> void:
	var blocker: String = provider.checkpoint_blocker()
	var result: int = provider.save_state()
	check(blocker == reason and result == ERR_BUSY and provider.blocked_reason == reason and not FileAccess.file_exists(file),
		"%s blocks with \"%s\" (got \"%s\")" % [label, reason, blocker])

func _vec(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _array(at: Vector3) -> Array:
	return [at.x, at.y, at.z]

func _bytes(file: String) -> String:
	return FileAccess.get_file_as_string(file) if FileAccess.file_exists(file) else ""

func _parse(file: String) -> Variant:
	var parser := JSON.new()
	return parser.data if FileAccess.file_exists(file) and parser.parse(_bytes(file)) == OK else null

func _canonical(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))

func _write_raw(file: String, contents: String) -> void:
	var handle := FileAccess.open(file, FileAccess.WRITE)
	handle.store_string(contents)
	handle.close()

func _cleanup(file: String) -> void:
	var directory := file.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		return
	for entry_name in DirAccess.get_files_at(directory):
		if entry_name == file.get_file() or entry_name.begins_with(file.get_file() + "."):
			DirAccess.remove_absolute(directory.path_join(entry_name))

func _free(world: Dictionary) -> void:
	_cleanup(world.path)
	world.level.free()

# ------------------------------------------------------------------ schema

func _schema_and_validation() -> void:
	var world := _world("schema")
	var provider: Node = world.save
	var bike: Node3D = world.bike
	var walking: Dictionary = provider.snapshot_state()
	check(not walking.is_empty() and int(walking.version) == Save.VERSION and not walking.has("bicycle") and provider.validate_snapshot(walking).is_empty(),
		"walking checkpoint keeps the unchanged schema-4 layout without a bicycle section")
	bike.mount_here()
	var mounted: Dictionary = provider.snapshot_state()
	if not check(not mounted.is_empty() and mounted.get("bicycle") is Dictionary, "stationary grounded clear rider produces a checkpoint (%s)" % provider.blocked_reason):
		_free(world)
		return
	var section: Dictionary = mounted.bicycle
	var seat := _vec(section.position)
	var stand := _vec(mounted.player.position)
	var heading := float(section.yaw)
	check(int(mounted.version) == Save.VERSION and int(section.version) == Mounted.VERSION and section.mounted == true
		and seat.is_equal_approx(bike.global_position) and is_equal_approx(heading, bike.yaw) and section.size() == 4,
		"mounted section records exactly the bicycle pose inside the schema-4 container")
	check(Mounted.footprint_gap(stand, seat, heading) >= Mounted.STAND_RADIUS and Vector2(stand.x - seat.x, stand.z - seat.z).length() <= 1.61
		and is_equal_approx(float(mounted.player.yaw), heading), "saved explorer is a standing spot beside the frame, never the seat")
	check(provider.validate_snapshot(mounted).is_empty(), "mounted checkpoint validates")
	var side := Vector3(cos(heading), 0.0, -sin(heading))
	var overlap: Dictionary = mounted.duplicate(true)
	overlap.player.position = section.position.duplicate()
	check(provider.validate_snapshot(overlap) == "saved explorer overlaps the bicycle", "standing spot on the seat is rejected as an overlap")
	overlap.player.position = _array(seat + side * 0.55)
	check(provider.validate_snapshot(overlap) == "saved explorer overlaps the bicycle", "standing spot brushing the frame is rejected as an overlap")
	overlap.player.position = _array(seat + side * 4.0)
	check(provider.validate_snapshot(overlap) == "saved explorer is not beside the bicycle", "standing spot far from the frame is rejected")
	for corrupt in [["mounted", false], ["mounted", "yes"], ["version", "1"], ["version", 1.5], ["version", 0], ["version", null],
		["yaw", "north"], ["position", [1.0, 2.0]], ["position", [500.0, 0.0, 500.0]]]:
		var bad: Dictionary = mounted.duplicate(true)
		bad.bicycle[corrupt[0]] = corrupt[1]
		var reason: String = provider.validate_snapshot(bad)
		check(not reason.is_empty() and reason != "unsupported version", "bicycle %s %s is recoverable corruption (%s)" % [corrupt[0], JSON.stringify(corrupt[1]), reason])
	var shapeless: Dictionary = mounted.duplicate(true)
	shapeless.bicycle = "seated"
	check(provider.validate_snapshot(shapeless) == "invalid bicycle", "a non-object bicycle section is corruption")
	var early: Dictionary = mounted.duplicate(true)
	early.version = 2
	for section_name in ["vehicles", "inventory", "progression"]:
		early.erase(section_name)
	check(provider.validate_snapshot(early) == "invalid bicycle", "a pre-schema-3 file cannot carry a seat")
	var future: Dictionary = mounted.duplicate(true)
	future.bicycle.version = 2
	check(provider.validate_snapshot(future) == "unsupported version", "a newer bicycle section is a protected future file")
	future.clock = "also corrupt"
	check(provider.validate_snapshot(future) == "unsupported version", "a newer bicycle section wins over unrelated corruption")
	_free(world)

# ------------------------------------------------------------------ save gating

func _save_gating() -> void:
	var world := _world("gating")
	var level: Node3D = world.level
	var provider: Node = world.save
	var bike: Node3D = world.bike
	var file: String = world.path
	bike.mount_here()
	var hookless := HooklessBicycle.new()
	level.add_child(hookless)
	level.bicycle = hookless
	level.player.seated_vehicle = hookless
	check(not provider.get_status().mounted_checkpoints, "a bicycle without persistence hooks disables mounted checkpoints")
	_expect_blocked(provider, file, "step off your bicycle before saving", "rider of a hookless bicycle")
	level.bicycle = bike
	level.player.seated_vehicle = bike
	hookless.free()
	check(provider.get_status().mounted_checkpoints, "the published hooks enable mounted checkpoints")
	bike.speed = 2.5
	_expect_blocked(provider, file, "stop the bicycle before saving", "pedalling rider")
	bike.speed = -0.4
	_expect_blocked(provider, file, "stop the bicycle before saving", "reversing rider")
	bike.speed = 0.0
	bike.planar_speed = 0.4
	_expect_blocked(provider, file, "stop the bicycle before saving", "rider still sliding after a bump")
	bike.planar_speed = 0.0
	bike.airborne = true
	_expect_blocked(provider, file, "land the bicycle before saving", "airborne hop")
	bike.airborne = false
	bike.grounded = false
	_expect_blocked(provider, file, "land the bicycle before saving", "rider rolling off a drop")
	bike.grounded = true
	bike.crashed = true
	_expect_blocked(provider, file, "recovering from a bicycle crash", "crash in progress")
	bike.crashed = false
	bike.hull_reason = "something is pressing against the bicycle"
	_expect_blocked(provider, file, "something is pressing against the bicycle", "collision-unsafe pose")
	bike.hull_reason = "no stable ground under the bicycle"
	_expect_blocked(provider, file, "no stable ground under the bicycle", "unsupported wheels")
	bike.hull_reason = ""
	level.player.impact_recovery = 0.4
	_expect_blocked(provider, file, "recovering from an impact", "impact recovery")
	level.player.impact_recovery = 0.0
	# The bicycle's published facts veto a permissive verdict.
	bike.verdict = ""
	bike.speed = 3.0
	_expect_blocked(provider, file, "stop the bicycle before saving", "moving facts under an empty verdict")
	bike.speed = 0.0
	bike.airborne = true
	_expect_blocked(provider, file, "land the bicycle before saving", "airborne facts under an empty verdict")
	bike.airborne = false
	bike.crashed = false
	bike.verdict = null
	var other := Node3D.new()
	level.add_child(other)
	level.player.seated_vehicle = other
	_expect_blocked(provider, file, "bicycle seat state is changing", "explorer seated on something other than this bicycle")
	level.driving.active = true
	_expect_blocked(provider, file, "leave the vehicle first", "explorer driving a car")
	level.driving.active = false
	level.player.seated_vehicle = bike
	other.free()
	var forward := Vector3(sin(bike.yaw), 0.0, cos(bike.yaw))
	var actor: Node3D = level.residents.actors.values()[0]
	var home := actor.global_position
	actor.global_position = bike.global_position + forward * 0.9
	_expect_blocked(provider, file, "something is pressing against the bicycle", "resident body (possibly physics-disabled) against the frame")
	actor.global_position = home
	var side := Vector3(cos(bike.yaw), 0.0, -sin(bike.yaw))
	for offset in [side, -side, side * 1.4, -side * 1.4, -forward * 1.6, forward * 1.6]:
		provider.blocked_spots.append(bike.global_position + offset)
	_expect_blocked(provider, file, "no room to step off the bicycle here", "rider boxed in with nowhere to stand")
	provider.blocked_spots.clear()
	level.police_assistance.checkpoint_blocked = true
	_expect_blocked(provider, file, "police response in progress", "stationary rider during a police response")
	level.police_assistance.checkpoint_blocked = false
	level.combat.downed = 1.0
	_expect_blocked(provider, file, "fight in progress", "stationary rider beside a fight")
	level.combat.downed = 0.0
	# A wall between the frame and one side: the explorer is never saved across it.
	var wall := StaticBody3D.new()
	wall.collision_layer = 2
	var box := BoxShape3D.new()
	box.size = Vector3(0.1, 3.0, 4.0)
	var shape := CollisionShape3D.new()
	shape.shape = box
	wall.add_child(shape)
	level.add_child(wall)
	wall.global_transform = Transform3D(Basis(Vector3.UP, bike.yaw), bike.global_position + side * 0.6 + Vector3.UP * 1.5)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var walled: Dictionary = provider.snapshot_state()
	var stand := _vec(walled.player.position) if not walled.is_empty() else Vector3.INF
	check(not walled.is_empty() and (stand - bike.global_position).dot(side) < -0.9, "the standing spot is chosen on the bicycle's side of a wall")
	wall.free()
	await get_tree().physics_frame
	check(level.player.seated_vehicle == bike and bike.active and bike.mutations() == 0, "no blocked attempt dismounted, moved or re-parked the rider")
	check(level.police_assistance.interruptions.is_empty(), "waiting on the police barrier never interrupts the response")
	check(provider.writes == 0 and provider.reads == 0, "blocked attempts never touch the slot")
	check(provider.save_state() == OK and provider.writes == 1 and FileAccess.file_exists(file), "the stationary rider saves immediately once safe")
	_free(world)

# ------------------------------------------------------------------ queue

func _queue_coalescing() -> void:
	var world := _world("queue")
	var provider: Node = world.save
	var bike: Node3D = world.bike
	bike.mount_here()
	bike.speed = 3.0
	var first: Dictionary = provider.request_save("manual")
	check(first.state == "queued" and first.reason == "stop the bicycle before saving"
		and first.message == "Save queued until it is safe: stop the bicycle before saving."
		and provider.get_status().pending.active and provider.get_status().pending.source == "manual",
		"a manual request while riding queues with the bicycle's own reason")
	for index in 5:
		provider.request_save("manual")
		provider.request_save("autosave")
	check(provider.writes == 0 and provider.reads == 0 and provider.get_status().pending.source == "manual" and resolved.is_empty(),
		"repeated requests coalesce into one waiting manual request with no slot access")
	var checks_before: int = bike.count("save_blocker")
	_ticks(provider, 10.0, STEP)
	var polls: int = bike.count("save_blocker") - checks_before
	check(polls >= 36 and polls <= 42 and provider.writes == 0 and provider.reads == 0,
		"a blocked request re-checks at most every 0.25 s and never touches the slot (%d checks in 10 s)" % polls)
	check(provider.get_status().pending.waiting_for == "stop the bicycle before saving"
		and provider.last_result == "Save queued until it is safe: stop the bicycle before saving.", "status keeps the truthful waiting reason")
	bike.speed = 0.0
	bike.airborne = true
	_ticks(provider, 0.3, STEP)
	check(provider.get_status().pending.waiting_for == "land the bicycle before saving" and provider.writes == 0, "a hop is waited out, not saved")
	bike.airborne = false
	var taken := _ticks_until(provider, func(): return provider.writes > 0, 1.0, STEP)
	check(provider.writes == 1 and taken > 0 and taken <= 16 and not provider.get_status().pending.active,
		"the queued save writes once within one poll of the rider coming to rest (%d ticks)" % taken)
	check(resolved.size() == 1 and resolved[0].state == "saved" and resolved[0].source == "manual", "exactly one completion notice for the queued request")
	var written = _parse(world.path)
	check(written is Dictionary and written.get("bicycle") is Dictionary and provider.validate_snapshot(written).is_empty(), "the written checkpoint is the mounted one")
	_ticks(provider, 20.0, 0.05)
	check(provider.writes == 1 and resolved.size() == 1, "nothing more is written once the request is satisfied")
	_free(world)

func _queue_autosave_and_pause() -> void:
	var world := _world("autosave")
	var level: Node3D = world.level
	var provider: Node = world.save
	var bike: Node3D = world.bike
	bike.mount_here()
	bike.speed = 2.0
	_ticks(provider, 29.9, 0.05)
	check(provider.writes == 0 and not provider.get_status().pending.active, "no autosave request before the interval")
	_ticks(provider, 0.2, 0.05)
	check(provider.get_status().pending.active and provider.get_status().pending.source == "autosave" and provider.writes == 0,
		"an autosave while riding waits as a queued request")
	_ticks(provider, 5.0, 0.05)
	check(provider.writes == 0 and provider.reads == 0, "the waiting autosave does not touch the slot")
	provider.request_save("manual")
	check(provider.get_status().pending.source == "manual", "a manual request upgrades the queued autosave")
	level.paused = true
	bike.speed = 0.0
	_ticks(provider, 3.0, 0.05)
	check(provider.writes == 0 and provider.get_status().pending.active, "paused menus hold the queued request")
	level.paused = false
	_ticks(provider, 0.3, 0.05)
	check(provider.writes == 1 and not provider.get_status().pending.active, "the first safe unpaused moment completes it")
	_ticks(provider, 29.0, 0.05)
	check(provider.writes == 1, "a completed save restarts the autosave interval")
	_ticks(provider, 1.5, 0.05)
	check(provider.writes == 2 and resolved.size() == 1, "the next autosave writes at once when safe and is not announced")
	_free(world)

func _failure_backoff() -> void:
	var world := _world("failure")
	var provider: Node = world.save
	var bike: Node3D = world.bike
	bike.mount_here()
	var good: String = world.path
	# The parent directory never exists: every write attempt fails to open its temporary.
	provider.path = root_path.path_join("missing-parent/failure.json")
	var immediate: Dictionary = provider.request_save("manual")
	check(immediate.state == "failed" and str(immediate.message).begins_with("Could not save (error") and provider.writes == 1 and resolved.is_empty(),
		"an immediate failure is returned to the caller, not announced twice")
	provider.request_save("manual")
	provider.request_save("manual")
	check(provider.writes == 1 and provider.get_status().pending.attempts == 1, "repeated requests during the back-off join the scheduled retry")
	provider.cancel_pending_save("fixture")
	resolved.clear()
	_ticks(provider, 30.05, 0.05)
	check(provider.writes == 2 and provider.get_status().pending.attempts == 1 and provider.get_status().pending.active,
		"a failed autosave keeps its request")
	check(resolved.size() == 1 and resolved[0].state == "failed" and resolved[0].retrying, "the first polled failure is announced once")
	var reads_after := int(provider.reads)
	_ticks(provider, 60.0, 0.05)
	check(provider.writes == 5 and provider.reads == reads_after + 9 and resolved.size() == 1,
		"failures retry after 5, 10 and 20 s: three more attempts in a minute, never a busy loop (%d writes)" % provider.writes)
	provider.path = good
	bike.speed = 2.0
	_ticks(provider, 6.0, 0.05)
	check(provider.writes == 5 and provider.get_status().pending.waiting_for == "stop the bicycle before saving",
		"a retry that falls due while riding waits instead of writing")
	var reads_waiting := int(provider.reads)
	_ticks(provider, 2.0, 0.05)
	check(provider.reads == reads_waiting and provider.writes == 5, "waiting after a failure still never touches the slot")
	bike.speed = 0.0
	_ticks(provider, 0.3, 0.05)
	check(provider.writes == 6 and provider.save_count == 1 and not provider.get_status().pending.active and FileAccess.file_exists(good),
		"the next safe moment completes the retried save")
	check(resolved.size() == 2 and resolved[1].state == "saved", "completion after the failure is announced")
	_free(world)

func _cancel_exit_restart() -> void:
	var world := _world("cancel")
	var level: Node3D = world.level
	var provider: Node = world.save
	var bike: Node3D = world.bike
	var file: String = world.path
	bike.mount_here()
	bike.speed = 2.0
	provider.request_save("manual")
	check(provider.cancel_pending_save("leaving") and not provider.get_status().pending.active
		and resolved.size() == 1 and resolved[0].state == "cancelled", "cancel drops and announces the waiting request")
	bike.speed = 0.0
	_ticks(provider, 5.0, 0.05)
	check(provider.writes == 0 and not FileAccess.file_exists(file) and not provider.cancel_pending_save(), "a cancelled request is never written later")
	bike.speed = 2.0
	provider.request_save("manual")
	level.remove_child(provider)
	check(not provider.get_status().pending.active, "leaving the scene discards the queued request")
	level.add_child(provider)
	bike.speed = 0.0
	_ticks(provider, 5.0, 0.05)
	check(provider.writes == 0 and not FileAccess.file_exists(file), "a request from a left scene is not replayed")
	bike.speed = 2.0
	provider.request_save("manual")
	provider.free()
	var next := FixtureSave.new()
	level.add_child(next)
	next.setup(level, file)
	bike.speed = 0.0
	_ticks(next, 10.0, 0.05)
	check(not next.get_status().pending.active and next.writes == 0 and not FileAccess.file_exists(file),
		"a restarted session begins with no queued request and writes nothing early")
	bike.speed = 2.0
	next.request_save("manual")
	next._write_blocked = true
	next.tick(0.05)
	check(not next.get_status().pending.active and next.writes == 0 and next.last_result == Save.WRITE_BLOCKED,
		"a protected slot drops the queued request with its reason")
	next._write_blocked = false
	bike.speed = 0.0
	check(next.save_state() == OK, "checkpoint for the discard case")
	bike.get_off(Vector3(13.0, 0.0, 10.0))
	level.combat.downed = 1.0
	var waiting: Dictionary = next.request_save("manual")
	var discarded: Array = []
	next.pending_save_resolved.connect(func(result: Dictionary): discarded.append(result))
	var loaded: Dictionary = next.load_state()
	check(waiting.state == "queued" and loaded.ok and not next.get_status().pending.active and discarded.size() == 1 and discarded[0].state == "discarded",
		"a successful load discards a request made against the replaced world")
	level.combat.downed = 0.0
	var writes_after := int(next.writes)
	_ticks(next, 5.0, 0.05)
	check(next.writes == writes_after, "the discarded request is not written afterwards")
	_free(world)

# ------------------------------------------------------------------ restore

func _mounted_restore() -> void:
	var world := _world("restore")
	var level: Node3D = world.level
	var provider: Node = world.save
	var bike: Node3D = world.bike
	bike.mount_here()
	if not check(provider.save_state() == OK, "mounted checkpoint written"):
		_free(world)
		return
	var saved: Dictionary = _parse(world.path)
	var seat := _vec(saved.bicycle.position)
	var heading := float(saved.bicycle.yaw)
	var stand := _vec(saved.player.position)
	bike.get_off(Vector3(40.0, 0.0, 40.0))
	bike.global_position = Vector3(43.0, 0.0, 40.0)
	bike.yaw = 2.0
	level.world_time.total_minutes += 90.0
	level.missions.state = {"completed_ids": [], "active_id": "", "stage": 0, "score": 0, "case_engine": {"version": 1}}
	level.progression.state = {"version": 2, "money": 999}
	events.clear()
	bike.calls.clear()
	var missions_before: int = level.missions.restores
	var result: Dictionary = provider.load_state()
	check(result.ok and result.bicycle.state == "mounted" and not result.player_fallback and provider.last_load.bicycle.state == "mounted",
		"a mounted checkpoint restores the rider on the bicycle")
	check(bike.active and level.player.seated_vehicle == bike and bike.global_position.is_equal_approx(seat) and is_equal_approx(bike.yaw, heading)
		and Vector2(level.player.global_position.x - seat.x, level.player.global_position.z - seat.z).length() < 0.02,
		"bicycle and rider are back at the saved pose")
	check(not events.is_empty() and events.back() == "bicycle" and events.find("residents") < events.find("bicycle")
		and events.find("custody") < events.find("bicycle") and events.find("incidents") < events.find("bicycle"),
		"the bicycle restore runs after every fallible provider (%s)" % [events])
	check(bike.count("pose_blocker") == 1 and bike.count("restore_pose") == 1 and bike.count("park_beside_explorer") == 0,
		"one pose preflight and one atomic restore, no re-park")
	check(provider.last_result == "loaded checkpoint", "no fallback notes when the rider is restored faithfully (%s)" % provider.last_result)
	check(_canonical(level.missions.state) == _canonical(saved.missions) and level.missions.restores == missions_before + 1
		and _canonical(level.progression.state) == _canonical(saved.progression),
		"case progress, recorded evidence and the wallet restore exactly once alongside the rider")
	check(provider.checkpoint_blocker().is_empty(), "the restored rider may checkpoint again at once")
	var over: Dictionary = provider.load_state()
	check(not over.ok and over.reason == "step off your bicycle before loading a checkpoint" and bike.count("restore_pose") == 1 and bike.active,
		"a load over a seated rider is refused without touching the bicycle")
	bike.get_off(stand)
	var again: Dictionary = provider.load_state()
	bike.get_off(stand)
	var third: Dictionary = provider.load_state()
	check(again.ok and third.ok and int(level.missions.state.score) == int(saved.missions.score) and int(level.progression.state.money) == int(saved.progression.money)
		and level.missions.restores == missions_before + 3, "repeated loads restore the same rewarded score and wallet, never adding to them")
	_free(world)

func _restore_fallbacks() -> void:
	var world := _world("fallback")
	var level: Node3D = world.level
	var provider: Node = world.save
	var bike: Node3D = world.bike
	bike.mount_here()
	if not check(provider.save_state() == OK, "mounted checkpoint for fallback cases"):
		_free(world)
		return
	var saved: Dictionary = _parse(world.path)
	var seat := _vec(saved.bicycle.position)
	var stand := Vector3(float(saved.player.position[0]), float(saved.player.position[1]), float(saved.player.position[2]))
	var away := Vector3(40.0, 0.0, 40.0)
	bike.get_off(away)
	bike.global_position = Vector3(43.0, 0.0, 40.0)
	bike.pose_reason = "something is pressing against the bicycle"
	bike.calls.clear()
	var blocked: Dictionary = provider.load_state()
	check(blocked.ok and blocked.bicycle.state == "standing" and blocked.player_fallback and not level.player.is_seated()
		and level.player.global_position.is_equal_approx(stand) and bike.count("restore_pose") == 0 and bike.count("park_beside_explorer") == 1,
		"a blocked saved pose restores the explorer standing at the checked spot and re-parks the bicycle")
	check("you could not be put back on your bicycle where you stopped (something is pressing against the bicycle), so you start standing" in provider.last_result,
		"the standing fallback is explained in the load notice (%s)" % provider.last_result)
	check(Mounted.footprint_gap(level.player.global_position, bike.global_position, bike.yaw) >= Mounted.STAND_RADIUS,
		"the re-parked bicycle does not overlap the standing explorer")
	bike.pose_reason = ""
	bike.refuse_restore = "put away the phone before riding"
	bike.get_off(away)
	bike.calls.clear()
	var refused: Dictionary = provider.load_state()
	check(refused.ok and refused.bicycle.state == "standing" and refused.bicycle.reason == "put away the phone before riding"
		and bike.count("restore_pose") == 1 and not bike.active and not level.player.is_seated(), "a refused restore_pose leaves the explorer standing with its reason")
	bike.refuse_restore = ""
	var actor: Node3D = level.residents.actors.values()[3]
	var home := actor.global_position
	var resident_state: Dictionary = saved.duplicate(true)
	var actor_id := str(level.residents.actors.keys()[3])
	resident_state.residents.residents[actor_id].position = _array(seat)
	_write_raw(world.path, JSON.stringify(resident_state))
	bike.get_off(away)
	bike.calls.clear()
	var occupied: Dictionary = provider.load_state()
	check(occupied.ok and occupied.bicycle.state == "standing" and occupied.bicycle.reason == "someone is standing there"
		and bike.count("restore_pose") == 0 and not level.player.is_seated(), "a restored resident standing at the saved pose prevents the remount")
	actor.global_position = home
	_write_raw(world.path, JSON.stringify(saved))
	bike.lie = "unseated"
	bike.get_off(away)
	bike.calls.clear()
	var unseated: Dictionary = provider.load_state()
	check(unseated.ok and unseated.bicycle.state == "standing" and not level.player.is_seated() and level.player.global_position.is_equal_approx(stand),
		"a restore_pose that reports ok without seating anyone is not trusted")
	bike.lie = "offset"
	bike.get_off(away)
	bike.calls.clear()
	var offset: Dictionary = provider.load_state()
	check(offset.ok and offset.bicycle.state == "standing" and bike.count("recovery_exit_at") == 1 and not level.player.is_seated()
		and level.player.global_position.is_equal_approx(stand) and str(offset.bicycle.reason) == "the bicycle came to rest away from its saved spot",
		"a rider seated away from the saved pose is undone through the bicycle back to the checked spot")
	bike.lie = ""
	bike.get_off(away)
	bike.settling = true
	var minutes: float = level.world_time.total_minutes
	bike.calls.clear()
	var settling: Dictionary = provider.load_state()
	check(not settling.ok and settling.reason == "wait for your bicycle to come to rest before loading a checkpoint"
		and level.world_time.total_minutes == minutes and bike.mutations() == 0, "a riderless bicycle still settling refuses the load before anything changes")
	bike.settling = false
	var hookless := HooklessBicycle.new()
	level.add_child(hookless)
	level.bicycle = hookless
	var bare: Dictionary = provider.load_state()
	check(bare.ok and bare.bicycle.state == "standing" and bare.bicycle.reason == "the bicycle is not ready" and bare.player_fallback
		and not level.player.is_seated() and level.player.global_position.is_equal_approx(stand), "a build without bicycle hooks loads the rider standing, with a note")
	level.bicycle = bike
	hookless.free()
	bike.get_off(away)
	check(provider.save_state() == OK, "walking checkpoint for the re-park case")
	bike.global_position = Vector3(-30.0, 0.0, 30.0)
	events.clear()
	bike.calls.clear()
	var walking: Dictionary = provider.load_state()
	check(walking.ok and walking.bicycle.state == "parked" and events.back() == "park" and bike.count("restore_pose") == 0
		and bike.global_position.distance_to(level.player.global_position) < 5.5, "a walking checkpoint re-parks the bicycle beside the explorer")
	_write_raw(world.path, JSON.stringify(saved))
	level.incidents.fail_once = true
	bike.calls.clear()
	var before_late: Vector3 = level.player.global_position
	var late: Dictionary = provider.load_state()
	check(not late.ok and late.rollback_clean and bike.mutations() == 0 and not level.player.is_seated() and level.player.global_position.is_equal_approx(before_late),
		"a late provider refusal rolls back before the bicycle is ever touched")
	_free(world)

# ------------------------------------------------------------------ legacy and disk

func _legacy_and_disk() -> void:
	var world := _world("legacy")
	var level: Node3D = world.level
	var provider: Node = world.save
	var bike: Node3D = world.bike
	var file: String = world.path
	check(provider.save_state() == OK, "walking checkpoint written")
	var walking_bytes := _bytes(file)
	var walking: Dictionary = _parse(file)
	bike.mount_here()
	check(provider.save_state() == OK and _bytes(file + ".bak") == walking_bytes, "a mounted checkpoint rotates the walking one into .bak byte for byte")
	var mounted_bytes := _bytes(file)
	bike.get_off(Vector3(40.0, 0.0, 40.0))
	var fresh := FixtureSave.new()
	level.add_child(fresh)
	fresh.setup(level, file)
	var restored: Dictionary = fresh.load_state()
	check(restored.ok and restored.bicycle.state == "mounted" and bike.active, "a fresh provider remounts the rider from the file alone")
	bike.get_off(Vector3(40.0, 0.0, 40.0))
	var future: Dictionary = _parse(file)
	future.bicycle.version = 2
	var future_text := JSON.stringify(future)
	_write_raw(file, future_text)
	var read: Dictionary = fresh.read_snapshot()
	check(not read.ok and read.reason == "unsupported version" and fresh.get_status().write_blocked and fresh.write_snapshot(walking) == ERR_UNAVAILABLE
		and _bytes(file) == future_text and _bytes(file + ".bak") == walking_bytes, "a newer bicycle section blocks fallback and is never overwritten")
	fresh._write_blocked = false
	future.bicycle.version = "two"
	_write_raw(file, JSON.stringify(future))
	read = fresh.read_snapshot()
	check(read.ok and read.source == "backup" and not fresh.get_status().write_blocked, "a garbled bicycle version is recoverable: the backup loads")
	_write_raw(file, mounted_bytes)
	var legacy_missions := {"completed_ids": ["case_a"], "active_id": "", "stage": 0, "score": 10}
	var v3: Dictionary = walking.duplicate(true)
	v3.version = 3
	for section in ["vehicles", "incidents", "police_assistance"]:
		v3.erase(section)
	v3.missions = legacy_missions.duplicate(true)
	var v2: Dictionary = v3.duplicate(true)
	v2.version = 2
	v2.erase("inventory")
	v2.erase("progression")
	var v1: Dictionary = v2.duplicate(true)
	v1.version = 1
	v1.erase("deaths")
	v1.erase("equipment")
	for id in v1.residents.residents.keys():
		if not id in Save.Residents.LEGACY_RESIDENT_IDS:
			v1.residents.residents.erase(id)
	var cases := [["current schema-4 walking file with 40 residents", walking, false], ["schema-3 file", v3, true],
		["schema-2 file", v2, true], ["schema-1 file with the original 20 residents", v1, true]]
	for entry in cases:
		_cleanup(file)
		_write_raw(file, JSON.stringify(entry[1]))
		bike.calls.clear()
		var loaded: Dictionary = fresh.load_state()
		check(loaded.ok and loaded.bicycle.state == "parked" and bool(loaded.migrated) == bool(entry[2]) and not level.player.is_seated()
			and bike.count("restore_pose") == 0 and bike.count("park_beside_explorer") == 1,
			"%s loads standing, re-parks the bicycle and invents no seat (%s)" % [entry[0], str(loaded.get("reason", ""))])
	_free(world)
