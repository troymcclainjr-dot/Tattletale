extends Node
## One chapter checkpoint. No active combat or original-block globals are saved.
## A validated temporary file is renamed over the slot; the preceding valid slot
## is retained as .bak. Flush/rename is crash recovery, not a power-loss guarantee.
## Schema 4 adds the driving manager's remembered parked cars ("vehicles"). A load
## preflights every section before changing the world, and rolls back what it has
## applied if a scene restore still fails: never a silent half-restored world.
## A stationary, grounded, collision-clear rider may be saved: the optional
## "bicycle" section (city_bicycle_checkpoint.gd) remounts them last, after every
## fallible step, or stands them at the checked spot written as player.position.
## A save request that cannot be written yet waits in memory for the next safe
## moment (never on disk, never by dismounting or interrupting anything).
## Contracts: .work/priorities-five/persistence-contract.md,
## .work/five-priorities-20261101/save-contract.md
signal pending_save_resolved(result: Dictionary)
const Residents := preload("res://scripts/city/city_residents.gd")
const Mounted := preload("res://scripts/city/city_bicycle_checkpoint.gd")
const VERSION := 4
## Layout written while the driving manager has no persistence API (no vehicles).
const NO_VEHICLES_VERSION := 3
const DEFAULT_PATH := "user://pen_lucy_world_v1.json"
const MAX_BYTES := 262144
const AUTOSAVE_SECONDS := 30.0
const VEHICLE_API := ["snapshot_state", "validate_state", "preflight_state", "restore_state", "reset_persistent_state"]
const INCIDENT_API := ["snapshot_state", "validate_state", "restore_state"]
const INCIDENTS_VERSION := 1
const EMPTY_INCIDENTS := {"version": INCIDENTS_VERSION, "next_sequence": 1, "incidents": []}
## Early v1 checkpoints omitted equipment entirely: their historical defaults.
const LEGACY_EQUIPMENT := {"health": 100.0, "weapon": "fists", "ammo": 12, "reserve": 72}
const VEHICLES_SETTLING := "waiting for parked vehicles to settle"
const WRITE_BLOCKED := "Saving is paused to protect an incompatible checkpoint. Use Recover saving in Settings."
## A queued request re-checks the world this often; no disk access while it waits.
const POLL_SECONDS := 0.25
## Write failures retry after these delays, then every AUTOSAVE_SECONDS.
const RETRY_SECONDS := [5.0, 10.0, 20.0]
var level: Node3D
var path := DEFAULT_PATH
var enabled := false
var last_result := "not initialized"
## Why the current world cannot become a checkpoint ("" when it can).
var blocked_reason := ""
## Outcome of the latest load attempt, including explicit fallbacks.
var last_load: Dictionary = {}
var save_count := 0
var last_saved_unix := 0.0
var _elapsed := 0.0
var _write_blocked := false
var _preserved_files: Array[String] = []
## The one queued request: {} or {source, waiting_for, attempts, error, queued}.
var _pending: Dictionary = {}
var _poll_wait := 0.0
## checkpoint_blocker()'s capture of a safe mounted pose, for snapshot_state().
var _mounted_capture: Dictionary = {}

func setup(owner_level: Node3D, fixture_path := "") -> void:
	level = owner_level
	path = fixture_path if not fixture_path.is_empty() else DEFAULT_PATH
	var validation := DisplayServer.get_name() == "headless" or "--offscreen-validation" in OS.get_cmdline_user_args() or bool(level.get("offscreen_validation"))
	enabled = not validation or not fixture_path.is_empty()
	last_result = "ready" if enabled else "disabled for validation"
	_pending = {}
	_poll_wait = 0.0

## Leaving the scene (menu, quit, reload) discards a queued request: it lives in
## memory only, so no later session can replay it.
func _exit_tree() -> void:
	_pending = {}

func tick(delta: float) -> void:
	if not enabled or delta <= 0.0 or bool(level.get("paused")):
		return
	if _write_blocked:
		_drop_pending("unavailable", WRITE_BLOCKED)
		return
	_elapsed += delta
	if _elapsed >= AUTOSAVE_SECONDS:
		_elapsed = 0.0
		_queue("autosave")
	if _pending.is_empty():
		return
	_poll_wait -= delta
	if _poll_wait <= 0.0:
		_attempt_pending()

## Player or autosave request. Writes now when safe; otherwise one in-memory
## request waits for the next safe moment. Repeated requests coalesce (a manual
## request upgrades a queued autosave) and never add writes or disk reads.
## {state: saved|queued|failed|unavailable, reason, message, error, source}
func request_save(source := "manual") -> Dictionary:
	var kind := "autosave" if source == "autosave" else "manual"
	if not enabled:
		return {"state": "unavailable", "reason": last_result, "message": "Progress saving is unavailable in this session.", "error": ERR_UNAVAILABLE, "source": kind}
	if _write_blocked:
		_drop_pending("unavailable", WRITE_BLOCKED)
		return {"state": "unavailable", "reason": "write blocked", "message": WRITE_BLOCKED, "error": ERR_UNAVAILABLE, "source": kind}
	# During a failure back-off a repeated request joins the scheduled retry.
	var retrying := not _pending.is_empty() and int(_pending.attempts) > 0 and _poll_wait > 0.0
	_queue(kind)
	var result: Error = ERR_BUSY if retrying else _attempt_pending(false)
	if result == OK:
		return {"state": "saved", "reason": "", "message": "Progress saved.", "error": OK, "source": kind}
	if _pending.is_empty():
		return {"state": "unavailable", "reason": "write blocked", "message": WRITE_BLOCKED, "error": ERR_UNAVAILABLE, "source": kind}
	var failing := int(_pending.attempts) > 0 and str(_pending.waiting_for).is_empty()
	return {"state": "failed" if failing else "queued", "reason": str(_pending.waiting_for), "message": _pending_message(),
		"error": int(_pending.get("error", ERR_BUSY)), "source": str(_pending.source)}

## Explicit cancel (e.g. "Leave without saving"): the slot is left exactly as is.
func cancel_pending_save(reason := "cancelled") -> bool:
	if _pending.is_empty():
		return false
	_drop_pending("cancelled", "Queued save cancelled (%s). Your last checkpoint is unchanged." % reason)
	return true

func _queue(source: String) -> void:
	if _pending.is_empty():
		_pending = {"source": source, "waiting_for": "", "attempts": 0, "error": ERR_BUSY, "queued": false}
		_poll_wait = 0.0
	elif source == "manual":
		_pending.source = "manual"

## `polled`: a later retry from tick(). A caller's own attempt reports through its
## return value instead of the signal, so no outcome is announced twice.
func _attempt_pending(polled := true) -> Error:
	_poll_wait = POLL_SECONDS
	var result := save_state()
	if result == OK or _pending.is_empty():
		return result
	if result == ERR_UNAVAILABLE:
		_drop_pending("unavailable", WRITE_BLOCKED)
		return result
	_pending.queued = true
	if result == ERR_BUSY:
		_pending.waiting_for = blocked_reason if not blocked_reason.is_empty() else "a safe moment"
	else:
		# A failed write keeps the request and backs off: never a busy loop.
		_pending.waiting_for = ""
		_pending.attempts = int(_pending.attempts) + 1
		_pending.error = result
		var step := int(_pending.attempts) - 1
		_poll_wait = float(RETRY_SECONDS[step]) if step < RETRY_SECONDS.size() else AUTOSAVE_SECONDS
		if polled and int(_pending.attempts) == 1:
			pending_save_resolved.emit({"source": str(_pending.source), "state": "failed", "message": _pending_message(), "error": result, "retrying": true})
	last_result = _pending_message()
	return result

## Ends the queued request; only requests that actually had to wait are announced.
func _drop_pending(state: String, message: String) -> void:
	if _pending.is_empty():
		return
	var was := _pending
	_pending = {}
	last_result = message
	if bool(was.queued):
		pending_save_resolved.emit({"source": str(was.source), "state": state, "message": message, "error": ERR_UNAVAILABLE, "retrying": false})

## Any written checkpoint satisfies the queued request and restarts the autosave interval.
func _saved_checkpoint() -> void:
	_elapsed = 0.0
	var was := _pending
	_pending = {}
	if bool(was.get("queued", false)):
		pending_save_resolved.emit({"source": str(was.source), "state": "saved", "message": "Progress saved.", "error": OK, "retrying": false})

func _pending_message() -> String:
	if _pending.is_empty():
		return ""
	if int(_pending.attempts) > 0 and str(_pending.waiting_for).is_empty():
		return "Could not save (error %d). Your previous checkpoint is kept; trying again in %d s." % [int(_pending.error), ceili(maxf(_poll_wait, 0.0))]
	return "Save queued until it is safe: %s." % str(_pending.waiting_for)

func _pending_status() -> Dictionary:
	if _pending.is_empty():
		return {"active": false, "source": "", "waiting_for": "", "attempts": 0, "retry_in": 0.0, "message": ""}
	return {"active": true, "source": str(_pending.source), "waiting_for": str(_pending.waiting_for), "attempts": int(_pending.attempts),
		"retry_in": maxf(_poll_wait, 0.0) if int(_pending.attempts) > 0 else 0.0, "message": _pending_message()}

func can_checkpoint() -> bool:
	return checkpoint_blocker().is_empty()

## "" when the current world can become a checkpoint, otherwise why not.
func checkpoint_blocker() -> String:
	_mounted_capture = {}
	if level == null or level.player == null or level.world_time == null or level.residents == null or level.missions == null:
		return "world not ready"
	if int(level.residents.get_status().pending_routes) > 0:
		return "daily routes still loading"
	if level.player.impact_recovery > 0.0:
		return "recovering from an impact"
	if _bicycle_blocks_checkpoint():
		return "recovering from a bicycle crash"
	# A rider hears the bicycle's own reason first (stop, land, steady). Nothing
	# here dismounts anyone to make a save possible.
	var mounted: bool = level.player.has_method("is_seated") and level.player.is_seated()
	var seat := {}
	if mounted:
		seat = Mounted.seat_check(level)
		if not str(seat.reason).is_empty():
			return str(seat.reason)
	var assistance = level.get("police_assistance")
	if _assistance_blocks_checkpoint(assistance):
		return "police response in progress"
	var incidents = level.get("incidents")
	if incidents != null and incidents.has_method("blocks_checkpoint") and incidents.blocks_checkpoint():
		return "incident transition in progress"
	if level.get("driving") != null and level.driving.get("active") == true:
		return "leave the vehicle first"
	if level.get("law") != null:
		var law_state: Dictionary = level.law.get_status()
		if bool(law_state.get("busy", false)) or int(law_state.get("wanted", 0)) > 0 or bool(law_state.get("recovering", false)):
			return "police incident in progress"
	if level.get("combat") != null:
		var combat: Dictionary = level.combat.get_status()
		if int(combat.active_count) > 0 or int(combat.get("knocked_count", 0)) > 0 or float(combat.downed) > 0.0 or int(combat.combo) > 0 or bool(combat.reloading):
			return "fight in progress"
	if mounted:
		# The seat overlaps the frame by design: check a standing spot beside it.
		_mounted_capture = Mounted.capture(self, seat.facts)
		return str(_mounted_capture.reason)
	if safe_player_position(level.player.global_position).is_empty():
		return "no stable ground"
	return ""

func snapshot_state() -> Dictionary:
	blocked_reason = checkpoint_blocker()
	if not blocked_reason.is_empty():
		return {}
	# A rider's player.position is the checked standing spot beside the bicycle.
	var mounted := _mounted_capture.duplicate(true)
	var point: Vector3 = mounted.stand if not mounted.is_empty() else safe_player_position(level.player.global_position).position
	var heading: float = float(mounted.yaw) if not mounted.is_empty() else level.player.yaw
	var state := {"version": NO_VEHICLES_VERSION, "chapter": "pen_lucy", "saved_at": Time.get_unix_time_from_system(), "clock": {"total_minutes": level.world_time.total_minutes,
		"elapsed_seconds": level.world_time.elapsed_seconds}, "player": {"position": [point.x, point.y, point.z], "yaw": heading},
		"residents": level.residents.snapshot_state(), "missions": level.missions.snapshot_state(),
		"walk": {"visited": level.visited.keys(), "route_index": level.route_index}}
	if level.get("combat") != null:
		var combat: Dictionary = level.combat.get_status()
		state.equipment = {"health": combat.health, "weapon": combat.weapon, "ammo": combat.ammo, "reserve": combat.reserve}
		state.deaths = level.combat.death_snapshot()
		state.inventory = level.combat.equipment_snapshot()
		var selected: Dictionary = state.inventory.weapons[state.inventory.equipped]
		state.equipment.ammo = selected.ammo
		state.equipment.reserve = selected.reserve
	if level.get("progression") != null:
		state.progression = level.progression.snapshot_state()
	var assistance = level.get("police_assistance")
	if assistance != null and assistance.has_method("snapshot_state"):
		state.police_assistance = assistance.snapshot_state()
	if level.get("incidents") != null:
		var incidents := _incident_api()
		if incidents == null:
			blocked_reason = "incident persistence unavailable"
			return {}
		state.incidents = incidents.snapshot_state()
	var vehicles := _vehicle_api()
	if vehicles != null:
		var payload = vehicles.snapshot_state()
		if payload is Dictionary and payload.is_empty():
			# The vehicle owner's transient "not now". Waiting never drops the cars.
			blocked_reason = VEHICLES_SETTLING
			return {}
		state.version = VERSION
		state.vehicles = payload
	if not mounted.is_empty():
		state.bicycle = mounted.section
	return state

## One immediate attempt (exit path, fixtures); request_save() is the queued form.
func save_state() -> Error:
	if not enabled or _write_blocked:
		return ERR_UNAVAILABLE
	var state := snapshot_state()
	if state.is_empty():
		last_result = VEHICLES_SETTLING if blocked_reason == VEHICLES_SETTLING else "waiting until a checkpoint is safe: " + blocked_reason
		return ERR_BUSY
	var result := write_snapshot(state)
	if result == OK:
		save_count += 1
		last_saved_unix = float(state.saved_at)
		last_result = "saved"
		_saved_checkpoint()
	else:
		last_result = "save failed (%d); previous checkpoint retained" % result
	return result

func load_state() -> Dictionary:
	if not enabled:
		return {"ok": false, "partial": false, "reason": last_result}
	var assistance = level.get("police_assistance")
	if _assistance_blocks_checkpoint(assistance):
		last_load = {"ok": false, "partial": false, "reason": "wait for the police response to finish before loading"}
		return last_load.duplicate()
	if level.player != null and (level.player.impact_recovery > 0.0 or _bicycle_blocks_checkpoint()):
		last_load = {"ok": false, "partial": false, "reason": "wait until impact recovery finishes before loading"}
		return last_load.duplicate()
	if level.player != null and level.player.has_method("is_seated") and level.player.is_seated():
		last_load = {"ok": false, "partial": false, "reason": "step off your bicycle before loading a checkpoint"}
		return last_load.duplicate()
	if level.get("driving") != null and level.driving.get("active") == true:
		# Never relocate the occupied car or the seated explorer. The checkpoint
		# itself is fine, so saving is not paused.
		last_load = {"ok": false, "partial": false, "reason": "leave the vehicle before loading a checkpoint"}
		return last_load.duplicate()
	var resting := Mounted.load_blocker(level)
	if not resting.is_empty():
		last_load = {"ok": false, "partial": false, "reason": resting}
		return last_load.duplicate()
	var read := read_snapshot()
	if not bool(read.get("ok", false)):
		last_result = str(read.get("reason", "no checkpoint"))
		last_load = {"ok": false, "partial": false, "reason": last_result}
		read.partial = false
		return read
	var state: Dictionary = read.state
	var version := int(state.version)
	if _number(state.get("saved_at"), 0.0, Time.get_unix_time_from_system() + 86400.0):
		last_saved_unix = float(state.saved_at)
	# Schema validation is complete. Preflight every scene-dependent section
	# before changing the clock, wallet, cars or player.
	var refusal := _preflight(state)
	if not refusal.is_empty():
		_write_blocked = true
		return _refuse(read, version, refusal)
	var before := _rollback_point()
	level.world_time.total_minutes = float(state.clock.total_minutes)
	level.world_time.elapsed_seconds = float(state.clock.elapsed_seconds)
	_apply_equipment(state)
	_apply_progression(state)
	# Cars before the case clue and the explorer: clue placement and the player
	# check both avoid vehicles (layer 16), while car hull checks do not see the
	# explorer. A changed or blocked parking spot is an explicit car fallback.
	var vehicles := _vehicle_api()
	var vehicle_result: Dictionary = {}
	if version >= VERSION:
		var restored = vehicles.restore_state(state.vehicles)
		vehicle_result = restored if restored is Dictionary else {}
		if not bool(vehicle_result.get("ok", false)):
			var clean := _rollback(before)
			_write_blocked = true
			return _refuse(read, version, "vehicles unavailable: " + str(vehicle_result.get("reason", "restore refused")), clean)
	elif vehicles != null:
		# A checkpoint from before vehicle persistence cannot keep cars this
		# session remembered after it was written (as with legacy equipment).
		var reset_result: Variant = vehicles.call("reset_persistent_state")
		if reset_result is bool and not reset_result:
			var clean := _rollback(before)
			_write_blocked = true
			return _refuse(read, version, "vehicles unavailable: reset refused", clean)
		vehicle_result = {"ok": true, "restored": 0, "fallbacks": [], "reason": "reset for schema %d checkpoint" % version}
	if not level.missions.restore_state(state.missions):
		# Never leave a rebuilt-but-empty case: undo everything applied above.
		var clean := _rollback(before)
		_write_blocked = true
		return _refuse(read, version, "case unavailable", clean)
	var placement := _place_player(state)
	var placed := placement == "saved"
	# These providers include durable additive registries. A later provider may
	# still refuse: restore reversible state, but never claim that new deaths or
	# completed custody were undone when their APIs cannot do that.
	before.restore_late = true
	if state.has("deaths") and level.get("combat") != null and not level.combat.restore_deaths(state.deaths):
		var clean := _rollback(before)
		_write_blocked = true
		return _refuse(read, version, "death registry rejected", clean)
	var resident_result: Dictionary = level.residents.restore_state(state.residents)
	if not bool(resident_result.get("ok", true)):
		var clean := _rollback(before)
		_write_blocked = true
		return _refuse(read, version, "residents unavailable", clean)
	# Completed custody is durable like deaths. Apply after resident schedules so
	# they cannot reactivate a detained person. Active encounters are never saved.
	if assistance != null and assistance.has_method("restore_state"):
		var custody_result: Dictionary = assistance.restore_state(state.get("police_assistance", {"version": 1, "custody_ids": []}))
		if not bool(custody_result.get("ok", false)):
			var clean := _rollback(before)
			_write_blocked = true
			return _refuse(read, version, "custody unavailable: " + str(custody_result.get("reason", "restore refused")), clean)
	var incident_result: Dictionary = {}
	var incidents := _incident_api()
	if incidents != null:
		# Old checkpoints replace this session's incident history with an empty
		# legacy section; no future encounters leak backwards into an old save.
		var restored = incidents.restore_state(state.get("incidents", EMPTY_INCIDENTS).duplicate(true))
		incident_result = restored if restored is Dictionary else {}
		if not bool(incident_result.get("ok", false)):
			var clean := _rollback(before)
			_write_blocked = true
			return _refuse(read, version, "incidents unavailable: " + str(incident_result.get("reason", "restore refused")), clean)
	level.visited.clear()
	for id in state.walk.visited:
		level.visited[id] = true
	level.route_index = int(state.walk.route_index)
	# The bicycle goes last, so no later provider can refuse after a remount and it
	# never needs unwinding. It sees the restored residents, cars and incidents.
	var bicycle_result := Mounted.restore(self, state)
	var bicycle_state := str(bicycle_result.state)
	var remounted := bicycle_state == "mounted"
	# A rider restored standing is not where they saved: report it as a fallback.
	placed = remounted if state.has("bicycle") else placed
	var fallbacks := _count(vehicle_result.get("fallbacks", []))
	var notes := PackedStringArray()
	if bicycle_state == "unverified":
		notes.append("your bicycle seat could not be checked (%s); reload before continuing" % str(bicycle_result.reason))
	elif not remounted:
		# Seated exactly where the checkpoint was made needs no standing-spot notes.
		if state.has("bicycle"):
			notes.append("you could not be put back on your bicycle where you stopped (%s), so you start standing" % str(bicycle_result.reason))
		if placement == "nearby":
			notes.append("your saved spot was blocked, so you start at a checked spot nearby")
		elif placement == "current":
			notes.append("your saved spot was blocked, so you start where you arrived")
		elif placement == "unplaced":
			notes.append("your saved spot was blocked and no checked spot was free, so you stay where you were")
	if fallbacks > 0:
		notes.append("%d remembered car%s could not return to where you left %s" % [fallbacks, "" if fallbacks == 1 else "s", "it" if fallbacks == 1 else "them"])
	# The world a queued request described is gone; it is not written later.
	_drop_pending("discarded", "Queued save discarded because a checkpoint was loaded.")
	last_result = "loaded " + str(read.get("source", "checkpoint")) + ("" if notes.is_empty() else " (" + "; ".join(notes) + ")")
	var result := {"ok": true, "partial": false, "reason": last_result, "backup": read.get("backup", false), "source": read.get("source", "checkpoint"),
		"player_fallback": not placed, "residents": resident_result, "mission_restored": true, "version": version, "migrated": version < VERSION,
		"vehicles": vehicle_result, "vehicle_fallbacks": fallbacks, "incidents": incident_result, "bicycle": bicycle_result.duplicate(true)}
	last_load = {"ok": true, "partial": false, "reason": last_result, "source": result.source, "version": version, "migrated": version < VERSION,
		"player_fallback": not placed, "player_placement": placement, "vehicle_fallbacks": fallbacks, "vehicle_details": vehicle_result.get("fallbacks", []),
		"residents_fallback": int(resident_result.get("fallback", 0)), "bicycle": bicycle_result.duplicate(true)}
	return result

## A clean rollback restores the prior live state. If a provider cannot return
## it exactly, or durable death/custody changed, report partial and protect disk.
func _refuse(read: Dictionary, version: int, reason: String, clean := true) -> Dictionary:
	last_result = reason + ("; checkpoint retained without applying world state" if clean else "; checkpoint retained, but the previous live state could not be fully restored. Reload before continuing.")
	last_load = {"ok": false, "partial": not clean, "reason": last_result, "source": read.get("source", "checkpoint"), "version": version, "rollback_clean": clean}
	return {"ok": false, "partial": not clean, "reason": last_result, "backup": read.get("backup", false), "version": version, "mission_restored": false,
		"rollback_clean": clean}

## Read-only checks for every step load_state applies; "" when all may proceed.
func _preflight(state: Dictionary) -> String:
	var version := int(state.version)
	if state.has("incidents") or _incident_api() != null:
		var incident_error := _incidents_error(state.get("incidents", EMPTY_INCIDENTS))
		if not incident_error.is_empty():
			return incident_error
	if state.has("police_assistance"):
		var assistance = level.get("police_assistance")
		if assistance == null or not assistance.has_method("validate_state"):
			return "custody service unavailable"
		var custody_error := str(assistance.validate_state(state.police_assistance))
		if not custody_error.is_empty():
			return "custody unavailable: " + custody_error
	if not bool(level.missions.preflight_restore(state.missions)):
		return "case unavailable"
	var dead: Array = state.get("deaths", {}).get("dead", []).duplicate()
	if level.get("combat") != null and level.combat.has_method("dead_ids"):
		for id in level.combat.dead_ids():
			if not id in dead:
				dead.append(id)
	var contact_error := _required_contact_error(state.missions, dead)
	if not contact_error.is_empty():
		return contact_error
	if level.get("combat") != null:
		if version < 3 and not level.combat.validate_equipment(_legacy_inventory(state)):
			return "legacy equipment cannot migrate"
		if state.has("deaths"):
			var death_error := _deaths_compatible(state.deaths)
			if not death_error.is_empty():
				return death_error
	if version >= VERSION:
		var report = _vehicle_api().preflight_state(state.vehicles)
		if not report is Dictionary or not bool(report.get("ok", false)):
			return "vehicles unavailable: " + (str(report.get("reason", "refused")) if report is Dictionary else "malformed preflight")
	return ""

## Mirrors combat.restore_deaths, which must succeed once applied: no rollback
## exists for a death.
func _deaths_compatible(value: Dictionary) -> String:
	var current := {}
	if level.combat.has_method("dead_ids"):
		for id in level.combat.dead_ids():
			current[str(id)] = true
	var fresh := 0
	for id in value.dead:
		if not _death_identity(str(id)):
			return "death registry incompatible"
		fresh += int(not current.has(str(id)))
	var limit = level.combat.get("MAX_DEATHS")
	if (limit is int or limit is float) and current.size() + fresh > int(limit):
		return "death registry full"
	return ""

func _apply_equipment(state: Dictionary) -> void:
	if level.get("combat") == null:
		return
	if int(state.version) < 3:
		level.combat.health = float(state.get("equipment", LEGACY_EQUIPMENT).health)
		level.combat.restore_equipment(_legacy_inventory(state))
	else:
		level.combat.health = float(state.equipment.health)
		level.combat.restore_equipment(state.inventory)

## Old saves had one shared pistol magazine even while fists were out. Migrate
## into the weapon store, not the new fists' zero-round store. Early v1 omitted
## equipment: its historical defaults mean a live legacy load cannot retain
## future guns or wounds. Legacy files never carry a trusted inventory.
func _legacy_inventory(state: Dictionary) -> Dictionary:
	var legacy: Dictionary = state.get("equipment", LEGACY_EQUIPMENT)
	var migrated: Dictionary = level.combat.equipment_snapshot()
	for id in migrated.weapons:
		migrated.weapons[id] = {"owned": id in ["fists", "pistol"], "ammo": 0, "reserve": 0}
	migrated.equipped = str(legacy.weapon)
	migrated.weapons.pistol = {"owned": true, "ammo": int(legacy.ammo), "reserve": int(legacy.reserve)}
	return migrated

func _apply_progression(state: Dictionary) -> void:
	if level.get("progression") == null:
		return
	if int(state.version) >= 3:
		level.progression.restore_state(state.progression)
	else:
		# A legacy load replaces this session's future wallet/reputation too.
		level.progression.setup(level)
		level.progression.migrate_legacy(state.missions.completed_ids)
	level.progression.reconcile_cases(state.missions.completed_ids)

func _rollback_point() -> Dictionary:
	var player: Node3D = level.player
	var point := {"clock": [level.world_time.total_minutes, level.world_time.elapsed_seconds], "position": player.global_position,
		"yaw": player.yaw, "camera_yaw": player.camera_yaw, "safe": level.get("_safe_position")}
	if level.get("combat") != null:
		point.health = level.combat.health
		point.inventory = level.combat.equipment_snapshot()
		point.deaths = level.combat.death_snapshot().duplicate(true)
	point.residents = level.residents.snapshot_state().duplicate(true)
	var assistance = level.get("police_assistance")
	if assistance != null and assistance.has_method("snapshot_state"):
		point.police_assistance = assistance.snapshot_state().duplicate(true)
	var incidents := _incident_api()
	if incidents != null:
		point.incidents = incidents.snapshot_state().duplicate(true)
	if level.get("progression") != null:
		point.progression = level.progression.snapshot_state()
		# At startup progression is not begun yet; restore_state would mark it
		# loaded and stop the root from beginning a new game after a refusal.
		var loaded = level.progression.get("_session_loaded")
		point.progression_fresh = loaded == false or (loaded == null and int(point.progression.get("seq", 1)) == 0)
	if level.missions.has_method("snapshot_state"):
		point.missions = level.missions.snapshot_state()
	var vehicles := _vehicle_api()
	if vehicles != null:
		point.vehicles = vehicles.snapshot_state()
	return point

## Restore reversible providers and verify durable registries stayed unchanged.
## A late refusal must not report success merely because restore APIs returned OK.
func _rollback(point: Dictionary) -> bool:
	var clean := true
	level.world_time.total_minutes = point.clock[0]
	level.world_time.elapsed_seconds = point.clock[1]
	if point.has("inventory"):
		level.combat.health = point.health
		level.combat.restore_equipment(point.inventory)
	if point.has("progression"):
		if point.progression_fresh:
			level.progression.setup(level)
		elif not point.progression.is_empty():
			level.progression.restore_state(point.progression)
	if point.has("vehicles"):
		var vehicles := _vehicle_api()
		var payload = point.vehicles
		if payload is Dictionary and not payload.is_empty() and str(vehicles.validate_state(payload)).is_empty():
			var restored = vehicles.restore_state(payload)
			clean = restored is Dictionary and bool(restored.get("ok", false)) and _count(restored.get("fallbacks", [])) == 0
		else:
			var reset_result: Variant = vehicles.call("reset_persistent_state")
			clean = not (reset_result is bool and not reset_result)
	if point.has("missions"):
		clean = bool(level.missions.restore_state(point.missions)) and clean
	_put_player(point.position, point.yaw)
	level.player.camera_yaw = point.camera_yaw
	if point.safe is Vector3:
		level._safe_position = point.safe
	if bool(point.get("restore_late", false)):
		# Match load ordering: schedules, durable custody, then incident records.
		# Deaths are deliberately not restored additively as a fake rollback.
		var residents = level.residents.restore_state(point.residents)
		clean = residents is Dictionary and bool(residents.get("ok", true)) and int(residents.get("fallback", 0)) == 0 and clean
		if point.has("deaths"):
			clean = _same_ids(level.combat.death_snapshot(), point.deaths, "dead") and clean
		var assistance = level.get("police_assistance")
		if point.has("police_assistance") and assistance != null:
			var restored = assistance.restore_state(point.police_assistance)
			clean = restored is Dictionary and bool(restored.get("ok", false)) and clean
			clean = _same_ids(assistance.snapshot_state(), point.police_assistance, "custody_ids") and clean
		if point.has("incidents"):
			var incidents := _incident_api()
			if incidents == null:
				clean = false
			else:
				var restored = incidents.restore_state(point.incidents)
				clean = restored is Dictionary and bool(restored.get("ok", false)) and clean
				clean = incidents.snapshot_state() == point.incidents and clean
	return clean

## "saved"; else "nearby", a checked spot beside the saved one; else "current",
## a checked spot where the explorer already stands. "unplaced" leaves them
## there. Never a move into an obstacle.
func _place_player(state: Dictionary) -> String:
	var saved := _vector(state.player.position)
	var safe := safe_player_position(saved)
	if not safe.is_empty():
		_put_player(safe.position, float(state.player.yaw))
		return "saved"
	for origin in [saved, level.player.global_position]:
		var nearby := _nearby_safe(origin)
		if not nearby.is_empty():
			_put_player(nearby.position, float(state.player.yaw))
			return "nearby" if origin == saved else "current"
	return "unplaced"

func _nearby_safe(origin: Vector3) -> Dictionary:
	var here := safe_player_position(origin)
	if not here.is_empty():
		return here
	var space := level.get_world_3d().direct_space_state
	for radius in [0.8, 1.6, 2.6]:
		for step in 8:
			var angle := TAU * float(step) / 8.0
			var candidate := safe_player_position(origin + Vector3(sin(angle), 0.0, cos(angle)) * float(radius))
			if candidate.is_empty():
				continue
			# Same side of any wall or fence: never into a sealed interior.
			var sight := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 1.0, Vector3(candidate.position) + Vector3.UP * 1.0, 1 | 2, [level.player.get_rid()])
			if space.intersect_ray(sight).is_empty():
				return candidate
	return {}

func _put_player(at: Vector3, heading: float) -> void:
	level.player.global_position = at
	level.player.velocity = Vector3.ZERO
	level.player.current_speed = 0.0
	level.player.reset_jump()
	level.player.set_orbiting(false)
	level.player._orbit_basis_latched = false
	level.player.yaw = heading
	level.player.camera_yaw = heading
	level.player.update_camera()
	level._safe_position = at

func safe_player_position(point: Vector3) -> Dictionary:
	if not _in_bounds(point) or _inside_closed_shop(point):
		return {}
	var hit: Dictionary = level.ground_at(point)
	# Authored walk-in floors are valid checkpoints too; roofs/counters/vehicles
	# remain excluded. The capsule clearance test below still applies.
	if (hit.is_empty() or absf(point.y - hit.position.y) > 0.35) and level.get("shops") != null:
		var interior: Dictionary = level.shops.walkable_floor_at(point)
		if not interior.is_empty():
			hit = interior
	if hit.is_empty() or hit.normal.y < cos(deg_to_rad(40.0)) or absf(point.y - hit.position.y) > 0.35:
		return {}
	point.y = hit.position.y + 0.02
	# Distant residents may have disabled physics bodies. Reserve their real
	# locations explicitly so later activation/restore cannot overlap the player.
	for actor in level.residents.actors.values():
		if actor.get_meta("city_dead", false):
			continue
		var offset: Vector3 = point - actor.global_position
		if Vector2(offset.x, offset.z).length() < 0.66 and absf(offset.y) < 1.9:
			return {}
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = level.player._capsule.shape
	query.transform = Transform3D(Basis.IDENTITY, point + level.player._capsule.position)
	query.collision_mask = 2 | 8 | 16
	query.exclude = [level.player.get_rid()]
	query.margin = 0.005
	if not level.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return {}
	return {"position": point}

func _inside_closed_shop(point: Vector3) -> bool:
	# Older checkpoints can be inside a shop that this build has shuttered.
	# Terrain under that floor must not validate a spawn behind the locked door.
	var shops = level.get("shops")
	if shops == null or not shops.has_method("is_entry_open"):
		return false
	for entry in shops.definitions:
		if shops.is_entry_open(entry):
			continue
		var model: Node3D = shops.models.get(str(entry.id))
		if model == null:
			continue
		var local := model.to_local(point)
		if absf(local.x) < float(entry.width) * 0.5 + 0.35 and absf(local.z) < float(entry.depth) * 0.5 + 0.35:
			return true
	return false

func _in_bounds(point: Vector3) -> bool:
	if not point.is_finite() or absf(point.y) > 1000.0:
		return false
	var extent: Dictionary = level.level_data.get("terrain_extent", {})
	if extent.is_empty():
		return false
	var low := _vector(extent.min)
	var high := _vector(extent.max)
	return point.x > low.x + 2.5 and point.x < high.x - 2.5 and point.z > low.z + 2.5 and point.z < high.z - 2.5

func validate_snapshot(value) -> String:
	if not value is Dictionary:
		return "malformed checkpoint"
	if _newer(value, VERSION):
		return "unsupported version"
	if not _integer(value.get("version"), 1, VERSION):
		return "invalid version"
	if not value.get("chapter") is String or value.chapter != "pen_lucy":
		return "wrong chapter"
	var version := int(value.version)
	# A section written by a newer build protects the whole slot before any other
	# check: read_snapshot then neither falls back to an older backup nor writes.
	if _future_section(value, version):
		return "unsupported version"
	if value.has("incidents"):
		var incident_error := _incidents_error(value.incidents)
		if not incident_error.is_empty():
			return incident_error
	if value.has("police_assistance"):
		var assistance = level.get("police_assistance")
		if assistance == null or not assistance.has_method("validate_state"):
			return "unsupported version"
		var custody_error := str(assistance.validate_state(value.police_assistance))
		if not custody_error.is_empty():
			return "invalid custody: " + custody_error
	var vehicle_error := _vehicles_error(value.get("vehicles")) if version >= 4 else ""
	if vehicle_error == "unsupported version":
		return vehicle_error
	for section in ["clock", "player", "residents", "missions", "walk"]:
		if not value.get(section) is Dictionary:
			return "missing " + section
	if version >= 3:
		if not value.get("inventory") is Dictionary or level.get("combat") == null or not level.combat.validate_equipment(value.inventory):
			return "invalid inventory"
		if not value.get("progression") is Dictionary or level.get("progression") == null or not str(level.progression.validate_state(value.progression)).is_empty():
			return "invalid progression"
	if not vehicle_error.is_empty():
		return vehicle_error
	var clock: Dictionary = value.clock
	if version >= 2 and not value.has("deaths"):
		return "missing death registry"
	if value.has("deaths"):
		var death_error := _validate_deaths(value.deaths)
		if not death_error.is_empty():
			return death_error
	# Optional for early v1 checkpoints; only stable inventory/health is stored.
	if version >= 3 and not value.has("equipment"):
		return "missing equipment"
	if value.has("equipment"):
		if not value.equipment is Dictionary:
			return "invalid equipment"
		var equipment: Dictionary = value.equipment
		if version >= 3:
			var selected: String = str(value.inventory.equipped)
			var store: Dictionary = value.inventory.weapons[selected]
			if not _number(equipment.get("health"), 0.0, 100.0) or not equipment.get("weapon") is String or equipment.weapon != selected \
				or not _integer(equipment.get("ammo"), 0, 1000000000) or not _integer(equipment.get("reserve"), 0, 1000000000) \
				or equipment.ammo != store.ammo or equipment.reserve != store.reserve:
				return "equipment inventory mismatch"
		elif not _number(equipment.get("health"), 0.0, 100.0) or not _integer(equipment.get("ammo"), 0, 12) or not _integer(equipment.get("reserve"), 0, 72) or not equipment.get("weapon") in ["fists", "pistol"]:
			return "invalid equipment"
	if not _number(clock.get("total_minutes"), 0.0, 144000000.0) or not _number(clock.get("elapsed_seconds"), 0.0, 1000000000.0):
		return "invalid clock"
	var player: Dictionary = value.player
	if not _position(player.get("position")) or not _number(player.get("yaw"), -100000.0, 100000.0):
		return "invalid player"
	var residents: Dictionary = value.residents
	if not _integer(residents.get("version"), 1, 1) or not residents.get("residents") is Dictionary:
		return "invalid residents"
	var known: Dictionary = level.residents.actors
	if known.is_empty() or known.size() != level.residents.definitions.size():
		return "resident roster mismatch"
	if residents.residents.size() != known.size():
		# Only the exact historical twenty-ID set may omit appended residents.
		# Arbitrary truncated/mixed saves remain corrupt, even if their count is20.
		if residents.residents.size() != Residents.LEGACY_RESIDENT_IDS.size():
			return "resident roster mismatch"
		for legacy_id in Residents.LEGACY_RESIDENT_IDS:
			if not known.has(legacy_id) or not residents.residents.has(legacy_id):
				return "resident roster mismatch"
	for id in residents.residents:
		if not known.has(id) or not residents.residents[id] is Dictionary:
			return "unknown resident"
		var resident: Dictionary = residents.residents[id]
		if not _position(resident.get("position")) or not _number(resident.get("yaw"), -100000.0, 100000.0):
			return "invalid resident position"
		if not resident.get("activity") in ["home", "work", "leisure", "sleep"] or not _integer(resident.get("route_cursor"), 0, 10000) or not _integer(resident.get("slot"), 0, 5):
			return "invalid resident progress"
	var missions: Dictionary = value.missions
	if not missions.get("completed_ids") is Array or not missions.get("active_id") is String:
		return "invalid cases"
	var completed: Array = missions.completed_ids
	var cases: Dictionary = level.missions.save_schema()
	var unique: Dictionary = {}
	var score := 0
	var max_score := 0
	for definition in cases.values():
		max_score += int(definition.reward)
	for id in completed:
		if not id is String or not cases.has(id) or unique.has(id):
			return "invalid completed case"
		unique[id] = true
		score += int(cases[id].reward)
	if not _integer(missions.get("score"), 0, max_score) or int(missions.score) != score:
		return "case reward mismatch"
	var active: String = missions.active_id
	if (not active.is_empty() and (not cases.has(active) or unique.has(active))) or not _integer(missions.get("stage"), 0, int(cases.get(active, {"stages": 1}).stages) - 1):
		return "invalid case progress"
	if level.missions.has_method("validate_state"):
		# narrative-contract.md: validate_state(missions_section, whole_snapshot := {})
		# cross-checks story choices and replacement contacts against the deaths.
		var checker := Callable(level.missions, "validate_state")
		var case_error := str(checker.call(missions, value) if checker.get_argument_count() >= 2 else checker.call(missions))
		if not case_error.is_empty():
			return "invalid cases: " + case_error
	var contact_error := _required_contact_error(missions, value.get("deaths", {}).get("dead", []))
	if not contact_error.is_empty():
		return contact_error
	var walk: Dictionary = value.walk
	if not walk.get("visited") is Array or not _integer(walk.get("route_index"), 0, level.landmarks.size()):
		return "invalid walk"
	if walk.visited.size() != int(walk.route_index):
		return "walk progress mismatch"
	for index in int(walk.route_index):
		if walk.visited.count(str(level.landmarks[index].get("id", index))) != 1:
			return "unknown walk stop"
	if value.has("bicycle"):
		# Optional like incidents: written only for a safe rider, never by a build
		# older than schema 3. Older readers ignore it and stand the explorer clear.
		var bicycle = value.bicycle
		if version < NO_VEHICLES_VERSION or not bicycle is Dictionary or not _position(bicycle.get("position")):
			return "invalid bicycle"
		var bicycle_error := Mounted.validate(value)
		if not bicycle_error.is_empty():
			return bicycle_error
	return ""

## True when a nested section was written by a newer build than this one. Only an
## integer version above what this build declares counts: corrupt version values
## stay "invalid", so an older valid backup can still recover them.
func _future_section(value: Dictionary, version: int) -> bool:
	if _newer(value.get("incidents"), INCIDENTS_VERSION) or _newer(value.get("bicycle"), Mounted.VERSION):
		return true
	var missions = value.get("missions")
	var case_engine = level.missions.get("cases") if level.get("missions") != null else null
	if missions is Dictionary and _newer(missions.get("case_engine"), _declared(case_engine, "VERSION")):
		return true
	var assistance = level.get("police_assistance")
	var custody = assistance.get("custody") if assistance != null else null
	if _newer(value.get("police_assistance"), _declared(custody, "PERSIST_VERSION")):
		return true
	if version >= 3 and level.get("progression") != null and _newer(value.get("progression"), _declared(level.progression, "VERSION")):
		return true
	if _newer(value.get("residents"), _declared(level.residents, "STATE_VERSION")):
		return true
	if version >= 3 and level.get("combat") != null and _newer(value.get("inventory"), int(level.combat.equipment_snapshot().get("version", 1))):
		return true
	return _newer(value.get("deaths"), _declared(level.get("combat"), "DEATH_VERSION"))

## Incidents are optional for old saves; a present section is never discarded
## just because this build is missing its owning provider.
func _incident_api() -> Node:
	var incidents = level.get("incidents") if level != null else null
	if not is_instance_valid(incidents):
		return null
	for method in INCIDENT_API:
		if not incidents.has_method(method):
			return null
	return incidents

func _incidents_error(value) -> String:
	if _newer(value, INCIDENTS_VERSION):
		return "unsupported version"
	var incidents := _incident_api()
	if incidents == null:
		return "unsupported version"
	if not value is Dictionary or not _integer(value.get("version"), 1, INCIDENTS_VERSION):
		return "invalid incidents"
	var reason := str(incidents.validate_state(value))
	return "" if reason.is_empty() else "invalid incidents: " + reason

func _bicycle_blocks_checkpoint() -> bool:
	var bicycle = level.get("bicycle") if level != null else null
	return bicycle != null and bicycle.has_method("blocks_checkpoint") and bool(bicycle.blocks_checkpoint())

static func _assistance_blocks_checkpoint(assistance) -> bool:
	if assistance == null:
		return false
	if assistance.has_method("blocks_checkpoint"):
		return bool(assistance.blocks_checkpoint())
	return assistance.has_method("is_busy") and bool(assistance.is_busy())

## The missions owner chooses replacement witnesses; persistence checks its
## answer against both saved deaths and (during preflight) durable live deaths.
func _required_contact_error(missions: Dictionary, dead: Array) -> String:
	var active := str(missions.get("active_id", ""))
	if active.is_empty():
		return ""
	var required: Variant = []
	if level.missions.has_method("required_contacts"):
		required = level.missions.required_contacts(missions, dead)
	elif level.missions.has_method("case_steps"):
		var steps: Array = level.missions.case_steps(active)
		for index in range(int(missions.stage), steps.size()):
			required.append(str(steps[index].target))
	if not required is Array:
		return "invalid case progress"
	for id in required:
		if not id is String or id.is_empty():
			return "invalid case contact"
		if id in dead:
			return "case requires deceased contact"
	return ""

static func _same_ids(a: Dictionary, b: Dictionary, key: String) -> bool:
	var left: Array = a.get(key, []).duplicate()
	var right: Array = b.get(key, []).duplicate()
	left.sort()
	right.sort()
	return left == right

## The driving payload is the vehicle owner's schema; this build only decides
## whether it may hold it. A newer payload, or no persistence API at all, means
## the remembered cars must not be loaded and then overwritten.
func _vehicles_error(value) -> String:
	var vehicles := _vehicle_api()
	if vehicles == null:
		return "unsupported version"
	if not value is Dictionary or not _integer(value.get("version"), 1, 1000000000):
		return "invalid vehicles"
	if int(value.version) > _declared(vehicles, "PERSIST_VERSION"):
		return "unsupported version"
	var reason := str(vehicles.validate_state(value))
	return "" if reason.is_empty() else "invalid vehicles: " + reason

func _vehicle_api() -> Node:
	var driving = level.get("driving") if level != null else null
	if not is_instance_valid(driving):
		return null
	for method in VEHICLE_API:
		if not driving.has_method(method):
			return null
	return driving

func _validate_deaths(value) -> String:
	var supported := _declared(level.get("combat"), "DEATH_VERSION")
	if _newer(value, supported):
		return "unsupported version"
	if not value is Dictionary or not _integer(value.get("version"), 1, supported) or not value.get("dead") is Array or value.dead.size() > 4096:
		return "invalid death registry"
	var seen := {}
	for id in value.dead:
		if not id is String or id.is_empty() or id.length() > 96 or seen.has(id):
			return "invalid death identity"
		var known: bool = level.residents.actors.has(id)
		if level.get("npcs") != null:
			known = known or level.npcs.actors.has(id)
			if id.begins_with("crowd_") and level.npcs.crowd != null:
				var suffix: String = id.trim_prefix("crowd_")
				known = suffix.is_valid_int() and str(int(suffix)) == suffix and int(suffix) >= 0 and int(suffix) < level.npcs.crowd.residents.size()
		if not known:
			return "unknown death identity"
		seen[id] = true
	return ""

func read_snapshot() -> Dictionary:
	return _select_snapshot(_read_sources())

## One parsed/validated view of all three slots for each read or write attempt.
func _read_sources() -> Dictionary:
	return {"checkpoint": _read(path), "backup": _read(path + ".bak"), "temporary": _read(path + ".tmp")}

func _select_snapshot(sources: Dictionary) -> Dictionary:
	# Protect every recoverable slot, including a newer client's pending rename.
	for candidate in sources.values():
		if str(candidate.get("reason", "")) == "unsupported version":
			_write_blocked = true
			return candidate
	for source in ["checkpoint", "backup", "temporary"]:
		var candidate: Dictionary = sources[source]
		if source == "temporary" and FileAccess.file_exists(path):
			continue
		if bool(candidate.get("ok", false)):
			candidate.source = source
			candidate.backup = source == "backup"
			return candidate
	# An invalid existing file may be an older content revision or repairable.
	# A failed load never silently turns into a fresh autosave over those bytes.
	for candidate in sources.values():
		if str(candidate.get("reason", "")) != "no checkpoint":
			_write_blocked = true
			return candidate
	return sources.checkpoint

func _read(source: String) -> Dictionary:
	if not FileAccess.file_exists(source):
		return {"ok": false, "reason": "no checkpoint"}
	var file := FileAccess.open(source, FileAccess.READ)
	if file == null:
		return {"ok": false, "reason": "checkpoint unreadable"}
	if file.get_length() > MAX_BYTES:
		return {"ok": false, "reason": "checkpoint too large"}
	var contents := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(contents) != OK:
		return {"ok": false, "reason": "malformed checkpoint"}
	var parsed = parser.data
	var error := validate_snapshot(parsed)
	return {"ok": error.is_empty(), "reason": error, "state": parsed if error.is_empty() else {}}

func write_snapshot(state: Dictionary) -> Error:
	if not enabled or _write_blocked:
		return ERR_UNAVAILABLE
	if not validate_snapshot(state).is_empty():
		return ERR_INVALID_DATA
	var contents := JSON.stringify(state)
	if contents.to_utf8_buffer().size() > MAX_BYTES:
		return ERR_INVALID_DATA
	var temporary := path + ".tmp"
	var sources := _read_sources()
	_select_snapshot(sources)
	if _write_blocked:
		return ERR_UNAVAILABLE
	var existing: Dictionary = sources.checkpoint
	var existing_backup: Dictionary = sources.backup
	var existing_temporary: Dictionary = sources.temporary
	# Recovery from a valid backup can proceed, but retain rejected primary bytes
	# in a separately named file before replacing them with a clean checkpoint.
	var source_paths := {"checkpoint": path, "backup": path + ".bak", "temporary": temporary}
	for name in source_paths:
		var source: String = source_paths[name]
		var candidate: Dictionary = sources[name]
		if not bool(candidate.get("ok", false)) and FileAccess.file_exists(source):
			var preservation := _preserve_rejected(source)
			if preservation != OK:
				return preservation
	# Preserve the sole valid temporary snapshot before opening the new temp.
	if not bool(existing.get("ok", false)) and not bool(existing_backup.get("ok", false)) and bool(existing_temporary.get("ok", false)):
		var recovery := DirAccess.copy_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path + ".bak"))
		if recovery != OK:
			return recovery
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(contents)
	file.flush()
	var result := file.get_error()
	file.close()
	if result != OK or not bool(_read(temporary).get("ok", false)):
		return ERR_FILE_CANT_WRITE
	if bool(existing.get("ok", false)):
		result = DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".bak.tmp"))
		if result != OK:
			return result
		result = DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".bak.tmp"), ProjectSettings.globalize_path(path + ".bak"))
		if result != OK:
			return result
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))

func _preserve_rejected(source: String) -> Error:
	var destination := source + ".rejected-%d-%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	var result := DirAccess.copy_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(destination))
	if result == OK:
		_preserved_files.append(destination)
	return result

func get_status() -> Dictionary:
	return {"enabled": enabled, "path": path, "result": last_result, "saves": save_count, "write_blocked": _write_blocked, "age_seconds": maxf(0.0, Time.get_unix_time_from_system() - last_saved_unix) if last_saved_unix > 0.0 else -1.0, "preserved_files": _preserved_files.duplicate(),
		"version": VERSION, "vehicle_persistence": _vehicle_api() != null, "blocked_reason": blocked_reason, "last_load": last_load.duplicate(true),
		"mounted_checkpoints": Mounted.api(level) != null, "pending": _pending_status()}

func recover_saving() -> Error:
	# Explicit user action only: preserve every old candidate before allowing the
	# current world to become the new slot. A content mismatch must not erase data.
	if not enabled or not _write_blocked:
		return ERR_UNAVAILABLE
	var state := snapshot_state()
	if state.is_empty():
		return ERR_BUSY
	var suffix := ".recovery-%d-%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	var moved: Array[String] = []
	for source in [path, path + ".bak", path + ".tmp"]:
		if not FileAccess.file_exists(source):
			continue
		var result := DirAccess.rename_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(source + suffix))
		if result != OK:
			for previous in moved:
				DirAccess.rename_absolute(ProjectSettings.globalize_path(previous + suffix), ProjectSettings.globalize_path(previous))
			last_result = "Could not preserve the old checkpoint; saving remains blocked."
			return result
		moved.append(source)
	for source in moved:
		_preserved_files.append(source + suffix)
	_write_blocked = false
	var result := write_snapshot(state)
	if result == OK:
		save_count += 1
		last_saved_unix = float(state.saved_at)
		last_result = "Current progress saved. The old checkpoint is kept as a recovery copy."
		_saved_checkpoint()
	else:
		_write_blocked = true
		last_result = "New checkpoint failed; old progress remains in the recovery copies."
	return result

func _position(value) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for component in value:
		if not _number(component, -100000.0, 100000.0):
			return false
	return _in_bounds(_vector(value))

## Count of an API's fallback report (an Array of details or a plain number).
static func _count(value) -> int:
	if value is Array:
		return value.size()
	return maxi(0, int(value)) if _number(value, 0.0, 1000000.0) else 0

## An integer section version above what this build writes.
static func _newer(section, supported: int) -> bool:
	return section is Dictionary and _integer(section.get("version"), supported + 1, 1000000000)

## A script constant such as STATE_VERSION, or 1 when the owner declares none.
static func _declared(source, constant: String) -> int:
	var value = source.get(constant) if source != null else null
	return int(value) if _integer(value, 1, 1000000000) else 1

## The identity rule combat.restore_deaths applies to every saved entry.
static func _death_identity(id: String) -> bool:
	if id.is_empty() or id.length() > 64:
		return false
	for index in id.length():
		var code := id.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 95 or code == 45 or code == 46):
			return false
	return true

static func _number(value, low: float, high: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= low and float(value) <= high

static func _integer(value, low: int, high: int) -> bool:
	return _number(value, low, high) and float(value) == floorf(float(value))

static func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
