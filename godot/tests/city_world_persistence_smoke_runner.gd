extends Node
## Schema-4 checkpoints through the real disk read path in the actual exported
## world: frozen v1/v2/v3 files, vehicle round trips, corrupt and future vehicle
## records, rollback and duplicate prevention, active and dead cases.
## Legacy files use literal sections exactly as older builds wrote them; only
## scene-owned sections (residents, player spot, walk) come from this world.
## Every file is an isolated project fixture; the user's slot is never opened.
## Run: --headless --script res://tests/city_world_persistence_smoke.gd
##      [-- --persistence-run-id=<letters/digits/_/->]
const Save := preload("res://scripts/city/city_world_save.gd")
const VehicleScript := preload("res://scripts/city/city_vehicle.gd")
## Progression v1 as the sandbox-foundations build wrote it.
const PROGRESSION_V1 := {"version": 1, "origin": "new", "money": 285, "reputation": {"snitch": 6, "gangsta": 3},
	"items": {"cannabis": 1}, "purchases": {"pistol": 1, "ammo_pistol": 1, "cannabis": 1}, "weapons": ["pistol"],
	"rewarded_cases": ["lost_satchel"], "once": ["buy_weapon"], "flags": [], "actions": {"buy_weapon": 1, "case_resolved": 1},
	"history": [
		{"seq": 1, "action": "new_game", "key": "", "deltas": {}, "money": 0, "minute": 540, "note": "Arrived in Pen Lucy with $500"},
		{"seq": 2, "action": "buy_weapon", "key": "pistol", "deltas": {"gangsta": 3}, "money": -250, "minute": 552, "note": "Bought Pistol"},
		{"seq": 3, "action": "purchase", "key": "ammo_pistol", "deltas": {}, "money": -30, "minute": 553, "note": "Bought Pistol ammunition"},
		{"seq": 4, "action": "purchase", "key": "cannabis", "deltas": {}, "money": -35, "minute": 560, "note": "Bought Cannabis"},
		{"seq": 5, "action": "case_resolved", "key": "lost_satchel", "deltas": {"snitch": 6}, "money": 100, "minute": 590, "note": "Lost satchel"}],
	"seq": 5}
const INVENTORY_V1 := {"version": 1, "equipped": "pistol", "weapons": {"fists": {"owned": true, "ammo": 0, "reserve": 0},
	"pistol": {"owned": true, "ammo": 7, "reserve": 24}, "uzi": {"owned": false, "ammo": 0, "reserve": 0},
	"ak47": {"owned": false, "ammo": 0, "reserve": 0}}}
var level: Node3D
var provider: Node
var passes := 0
var failures := 0
var finished := false
var fixture := ""
var vehicle_api := false
var scene_sections: Dictionary = {}
var fresh_vehicles: Dictionary = {}
var moved_bytes := ""
var promoted_bytes := ""
var promoted_id := ""
var private_viewport: SubViewport

class DrivingStub extends Node3D:
	## Container-logic double for level.driving with a minimal payload schema.
	var active := false
	var vehicle: Node3D
	var refuse_preflight := false
	var refuse_sequence := -1
	var refuse_reset := false
	var fallbacks: Array = []
	var restores := 0
	var resets := 0
	var applied: Dictionary = {"version": 1, "sequence": 0, "vehicles": [], "parked_damage": []}

	func get_status() -> Dictionary:
		# Mission restore emits changed synchronously; the real level HUD reads
		# the replacement driving owner during that callback, including rollback.
		return {"active": active, "vehicle_id": "", "gear": "N", "speed_mph": 0.0,
			"prompt": "", "message": ""}

	func snapshot_state() -> Dictionary:
		return applied.duplicate(true)

	func validate_state(value) -> String:
		if not value is Dictionary or not Save._integer(value.get("version"), 1, 1) or not value.get("vehicles") is Array:
			return "fixture schema"
		return ""

	func preflight_state(_value) -> Dictionary:
		return {"ok": not refuse_preflight, "reason": "fixture preflight refusal" if refuse_preflight else "", "fallbacks": []}

	func restore_state(value) -> Dictionary:
		restores += 1
		if int(value.get("sequence", -2)) == refuse_sequence:
			return {"ok": false, "restored": 0, "fallbacks": [], "reason": "fixture restore refusal"}
		applied = value.duplicate(true)
		return {"ok": true, "restored": 0, "fallbacks": fallbacks.duplicate(true), "reason": ""}

	func reset_persistent_state() -> Variant:
		resets += 1
		if refuse_reset:
			return false
		applied = {"version": 1, "sequence": 0, "vehicles": [], "parked_damage": []}
		return null # The older void API remains supported.

class CaseRestoreFails extends Node3D:
	## Preflight passes, then rebuilding the saved active case fails late.
	var real: Node

	func get_status() -> Dictionary:
		return real.get_status()

	func _can_interact(at: Vector3) -> bool:
		return real._can_interact(at)

	func validate_state(section, snapshot: Dictionary = {}) -> String:
		return real.validate_state(section, snapshot)

	func save_schema() -> Dictionary:
		return real.save_schema()

	func case_steps(id: String) -> Array:
		return real.case_steps(id)

	func snapshot_state() -> Dictionary:
		return real.snapshot_state()

	func preflight_restore(_state: Dictionary) -> bool:
		return true

	func restore_state(state: Dictionary) -> bool:
		return str(state.get("active_id", "")).is_empty() and real.restore_state(state)

func _ready() -> void:
	_run.call_deferred()
	_watchdog()

func _watchdog() -> void:
	await get_tree().create_timer(900.0, true, false, true).timeout
	if not finished:
		check(false, "persistence fixture completes within 900 seconds (two cold world boots)")
		_finish()

func check(ok: bool, label: String) -> bool:
	print("[world_persistence] %s %s" % ["PASS" if ok else "FAIL", label])
	passes += int(ok)
	failures += int(not ok)
	return ok

func note(text: String) -> void:
	print("[world_persistence] note " + text)

func frames(count: int) -> void:
	for index in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func canonical(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))

## Silent parse (the static JSON.parse_string logs an engine ERROR on bad text,
## which the validation harness counts as a failure). Null when malformed.
func _parsed(text: String) -> Variant:
	var parser := JSON.new()
	return parser.data if parser.parse(text) == OK else null

func _run() -> void:
	if DisplayServer.get_name() != "headless" and not "--offscreen-validation" in OS.get_cmdline_user_args():
		check(false, "requires --headless or --offscreen-validation (never a user session)")
		_finish()
		return
	if DisplayServer.get_name() != "headless":
		get_tree().root.hide()
		private_viewport = SubViewport.new()
		private_viewport.name = "PrivateWorldPersistence"
		private_viewport.size = Vector2i(1280, 720)
		private_viewport.own_world_3d = true
		private_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(private_viewport)
		note("private real renderer: batch transforms remain exact")
	else:
		note("dummy renderer: batch counts and promotion deltas checked; exact transforms require separate offscreen run")
	var run_id := "manual"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--persistence-run-id="):
			run_id = arg.trim_prefix("--persistence-run-id=")
	var safe_id := not run_id.is_empty() and run_id.length() <= 64
	for character in run_id:
		safe_id = safe_id and character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
	if not check(safe_id, "fixture run id is a plain name"):
		_finish()
		return
	fixture = ProjectSettings.globalize_path("res://../.work/priorities-five/persistence-validation/%s/world.json" % run_id)
	DirAccess.make_dir_recursive_absolute(fixture.get_base_dir())
	_cleanup()
	if not await _boot():
		_finish()
		return
	await _capabilities()
	if scene_sections.is_empty():
		_finish()
		return
	await _vehicle_roundtrip()
	await _legacy_files()
	await _promoted_parked()
	_corrupt_vehicle_records()
	await _future_records()
	_transactional_rollback()
	_checkpoint_blocking()
	await _fresh_scene_reload()
	await _active_and_dead_cases()
	_cleanup()
	_finish()

func _boot() -> bool:
	var previous: Node = level if private_viewport != null else get_tree().current_scene
	var previous_id := previous.get_instance_id() if previous != null else 0
	var private_level: Node3D
	if private_viewport != null:
		if is_instance_valid(previous):
			previous.queue_free()
			await frames(4)
		var scene: PackedScene = load("res://scenes/city/pen_lucy.tscn")
		private_level = scene.instantiate()
		private_viewport.add_child(private_level)
	else:
		get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	await frames(4)
	level = null
	for index in 1800:
		var current: Node3D = private_level if private_viewport != null else get_tree().current_scene as Node3D
		if current != null and current.get_instance_id() != previous_id and current.get("level_ready") == true:
			level = current
			break
		await frames(1)
	if not check(level != null, "actual exported world boots"):
		return false
	level.pause_exploring()
	for index in 600:
		if int(level.residents.get_status().pending_routes) == 0:
			break
		await frames(1)
	provider = Save.new()
	level.add_child(provider)
	provider.setup(level, fixture)
	return check(provider.enabled and provider.path == fixture and not level.world_save.enabled,
		"isolated fixture provider enabled; production slot provider stays disabled")

func _capabilities() -> void:
	vehicle_api = true
	for method in Save.VEHICLE_API:
		vehicle_api = vehicle_api and level.driving.has_method(method)
	check(vehicle_api, "driving manager exposes snapshot/validate/preflight/restore/reset persistence")
	var state: Dictionary = await _checkpoint()
	if not check(not state.is_empty(), "stable grounded startup checkpoint"):
		return
	scene_sections = {"player": state.player.duplicate(true), "residents": state.residents.duplicate(true), "walk": state.walk.duplicate(true)}
	check(int(state.version) == Save.VERSION and state.get("vehicles") is Dictionary and provider.validate_snapshot(state).is_empty(),
		"fresh world writes schema 4 with a valid vehicle section before anything is remembered")
	check(JSON.stringify(state).to_utf8_buffer().size() < Save.MAX_BYTES * 0.5, "schema 4 stays well inside the slot size older builds enforce")
	if vehicle_api:
		fresh_vehicles = level.driving.snapshot_state()
		check(not fresh_vehicles.is_empty() and str(level.driving.validate_state(fresh_vehicles)).is_empty(),
			"nothing-remembered vehicle payload is still a valid, non-empty version-1 payload")

# --- New schema 4 vehicle round trip -----------------------------------------------

func _vehicle_roundtrip() -> void:
	if not check(vehicle_api, "vehicle round trip has the driving persistence API"):
		return
	var driving: Node = level.driving
	var car: Node3D = driving.starter
	if not check(is_instance_valid(car), "real starter car exists"):
		return
	var spawn := car.global_position
	if not check(await _drive_starter(car), "starter boarded, driven and parked through the real driving controls"):
		return
	check(car.global_position.distance_to(spawn) > 1.0, "parked starter now sits away from its spawn spot")
	car.apply_body_damage(35.0)
	car.receive_gunshot({"tire_index": 1}, car.global_position + Vector3.UP * 4.0)
	var saved: Dictionary = await _checkpoint()
	if not check(not saved.is_empty(), "parked damaged starter reaches a stable checkpoint"):
		return
	var record := _vehicle_record(saved.vehicles, str(car.vehicle_id))
	check(not record.is_empty() and _vec(record.get("position", [0, 0, 0])).distance_to(car.global_position) < 0.02
		and _sorted(record.get("flat_tires", [])) == [1] and absf(float(record.get("health", -1.0)) - float(car.health)) <= 0.01,
		"snapshot carries the parked pose, punctured tire and body damage")
	moved_bytes = JSON.stringify(saved)
	_fresh_slot(moved_bytes)
	var read: Dictionary = provider.read_snapshot()
	check(read.get("ok", false) and canonical(read.state.vehicles) == canonical(saved.vehicles), "vehicle section survives the disk round trip exactly")
	# Change everything the checkpoint owns, including the remembered car.
	driving.reset_persistent_state()
	await frames(2)
	var reset_car: Node3D = driving.starter
	check(is_instance_valid(reset_car) and reset_car.global_position.distance_to(spawn) < 0.05 and reset_car.flat_tires.is_empty()
		and is_equal_approx(float(reset_car.health), 100.0), "reset returns the starter to its spawn spot, repaired")
	level.progression.credit(77, "persistence mutation")
	level.world_time.total_minutes += 33.0
	var result: Dictionary = provider.load_state()
	await frames(2)
	check(result.get("ok", false) and int(result.get("version", 0)) == Save.VERSION and int(result.get("vehicle_fallbacks", -1)) == 0 and not result.get("migrated", true),
		"schema 4 load restores the remembered car without fallback")
	check(canonical(driving.snapshot_state()) == canonical(saved.vehicles), "restored vehicle payload equals the saved one exactly")
	var starter: Node3D = driving.starter
	check(is_instance_valid(starter) and starter.global_position.distance_to(_vec(record.get("position", [0, 0, 0]))) < 0.05
		and _sorted(starter.flat_tires) == [1] and absf(float(starter.health) - float(record.get("health", -1.0))) <= 0.01,
		"live starter is back at its parked pose with its damage and flat tire")
	check(int(level.progression.money) == int(saved.progression.money) and is_equal_approx(level.world_time.total_minutes, float(saved.clock.total_minutes)),
		"wallet and clock resume together with the cars")
	var bodies := _bodies_by_id()
	var second: Dictionary = provider.load_state()
	await frames(2)
	check(second.get("ok", false) and _bodies_by_id() == bodies and canonical(driving.snapshot_state()) == canonical(saved.vehicles),
		"repeated load keeps the same bodies and payload")
	check(_unique(bodies), "no live vehicle identity has two bodies")

func _drive_starter(car: Node3D) -> bool:
	var driving: Node = level.driving
	var size: Vector3 = driving._car_size(car)
	var door: Dictionary = {}
	for side in [1.0, -1.0]:
		door = driving._exit_spot(car, side * (size.x * .5 + .65), .25, true)
		if not door.is_empty():
			break
	if door.is_empty():
		note("no clear starter door")
		return false
	_stand(door.position)
	level.resume_exploring()
	await frames(10)
	if not driving.enter_vehicle(car):
		note("starter entry refused: " + str(driving.get_status().get("prompt", "")))
		level.pause_exploring()
		return false
	# Occupied: no checkpoint, and a load must refuse before touching anything.
	var slot := _bytes(fixture)
	var busy: int = provider.save_state()
	var reason: String = provider.checkpoint_blocker()
	check(busy == ERR_BUSY and reason == "leave the vehicle first" and _bytes(fixture) == slot, "no checkpoint while driving; slot bytes untouched")
	var inventory: Variant = canonical(level.combat.equipment_snapshot())
	var refused: Dictionary = provider.load_state()
	check(not refused.get("ok", true) and not refused.get("partial", true) and driving.active and driving.vehicle == car
		and canonical(level.combat.equipment_snapshot()) == inventory and not provider.get_status().write_blocked,
		"load while seated refuses without detaching, mutating inventory or pausing saves")
	driving.set_control_override(0.7, 0.0, 0.0, false)
	await frames(45)
	driving.set_control_override(0.0, 1.0, 0.0, true)
	for step in 120:
		await frames(1)
		if absf(float(car.speed)) <= 0.1:
			break
	driving.set_control_override(0.0, 0.0, 0.0, true)
	await frames(20)
	driving.clear_control_override()
	var exited: bool = driving.exit_vehicle(false)
	if not exited:
		exited = driving.exit_vehicle(true)
	await frames(4)
	level.pause_exploring()
	return exited and not driving.active

# --- Legacy files -------------------------------------------------------------------

func _legacy_files() -> void:
	for version in [1, 2, 3]:
		await _legacy_case(version)

## A session that knows more than any legacy file: a remembered car, future
## guns, wealth and wounds. Every legacy load must discard all of it.
func _future_session() -> void:
	if not moved_bytes.is_empty():
		_fresh_slot(moved_bytes)
		provider.load_state()
		await frames(2)
	level.combat.grant_weapon("ak47")
	level.combat.add_ammo("ak47", 100)
	level.combat.equip("ak47")
	level.combat.health = 21.0
	level.progression.credit(5000, "persistence future wealth")

func _legacy(version: int) -> Dictionary:
	var state := {"version": version, "chapter": "pen_lucy", "saved_at": 1793000000.0,
		"clock": {"total_minutes": 600.0 + version * 15.0, "elapsed_seconds": 1800.0 + version * 60.0},
		"player": scene_sections.player.duplicate(true), "residents": scene_sections.residents.duplicate(true),
		"missions": {"active_id": "", "stage": 0, "completed_ids": [], "score": 0}, "walk": scene_sections.walk.duplicate(true)}
	if version >= 2:
		state.equipment = {"health": 100.0, "weapon": "fists", "ammo": 3, "reserve": 19}
		state.deaths = {"version": 1, "dead": []}
		state.missions = {"active_id": "", "stage": 0, "completed_ids": ["lost_satchel"], "score": 100}
	if version >= 3:
		state.equipment = {"health": 82.0, "weapon": "pistol", "ammo": 7, "reserve": 24}
		state.inventory = INVENTORY_V1.duplicate(true)
		state.progression = PROGRESSION_V1.duplicate(true)
		state.deaths = {"version": 1, "dead": ["crowd_7"]}
	return state

func _legacy_case(version: int) -> void:
	var label := "v%d: " % version
	await _future_session()
	var bytes := JSON.stringify(_legacy(version))
	_fresh_slot(bytes)
	var result: Dictionary = provider.load_state()
	await frames(2)
	if not check(result.get("ok", false) and int(result.get("version", 0)) == version and result.get("migrated", false),
		label + "frozen file loads from disk as an explicit migration"):
		note(label + JSON.stringify(result))
	var economy: Node = level.progression
	var starting := int(economy.config.money.starting)
	match version:
		1:
			var inventory: Dictionary = level.combat.equipment_snapshot()
			check(level.combat.health == 100.0 and inventory.equipped == "fists" and inventory.weapons.pistol.owned
				and int(inventory.weapons.pistol.ammo) == 12 and int(inventory.weapons.pistol.reserve) == 72
				and not inventory.weapons.ak47.owned and not inventory.weapons.uzi.owned and int(economy.money) == starting,
				label + "equipmentless file restores historical defaults, not future guns, wealth or wounds")
		2:
			check(level.combat.weapon == "fists" and level.combat.ammo == 0 and level.combat.reserve == 0, label + "fists keep an empty fists store")
			level.combat.equip("pistol")
			check(level.combat.ammo == 3 and level.combat.reserve == 19 and not level.combat.equipment_snapshot().weapons.ak47.owned,
				label + "shared magazine migrates to the pistol without refill; future AK47 discarded")
			level.combat.equip("fists")
			var cash: int = economy.money
			check(cash == starting and not economy.reward_case("lost_satchel", 100) and int(economy.money) == cash
				and level.missions.completed_ids.has("lost_satchel") and level.missions.score == 100,
				label + "completed case kept and marked paid; its reward never replays")
			var again: Dictionary = provider.load_state()
			check(again.get("ok", false) and int(economy.money) == cash, label + "repeated legacy load pays nothing")
		3:
			check(canonical(level.combat.equipment_snapshot()) == canonical(INVENTORY_V1) and is_equal_approx(level.combat.health, 82.0),
				label + "inventory and health restore exactly")
			var status: Dictionary = economy.get_status()
			check(int(economy.money) == 285 and economy.reputation_value("snitch") == 6 and economy.reputation_value("gangsta") == 3
				and economy.item_count("cannabis") == 1 and "lost_satchel" in status.rewarded_cases and "pistol" in status.weapons_purchased,
				label + "frozen progression v1 payload is still accepted and restored (story data backward compatible)")
			check(level.combat.is_actor_dead("crowd_7"), label + "death registry applies")
	if vehicle_api:
		check(_semantics(level.driving.snapshot_state()) == _semantics(fresh_vehicles),
			label + "forgets cars remembered after it was written; starter back at spawn, repaired")
	check(_bytes(fixture) == bytes, label + "loading never rewrites the legacy file")
	var written: int = provider.save_state()
	var upgraded: Dictionary = provider.read_snapshot()
	check(written == OK and upgraded.get("ok", false) and int(upgraded.get("state", {}).get("version", 0)) == Save.VERSION and _bytes(fixture + ".bak") == bytes,
		label + "next save upgrades to schema 4 and keeps the legacy bytes as the backup")

# --- Promoted parked cars and changed geometry ------------------------------------

func _promoted_parked() -> void:
	if not check(vehicle_api and not moved_bytes.is_empty(), "promoted parked persistence has the API and a remembered starter"):
		return
	var parked = level.traffic.parked
	if not check(parked != null and parked.has_method("source_index") and not parked.records.is_empty() and parked.records[0].has("source_id"),
		"parked records expose stable source identities"):
		return
	_fresh_slot(moved_bytes)
	provider.load_state()
	await frames(2)
	var index := _quiet_parked_index()
	if not check(index >= 0, "positive control: untouched parked source is represented by its batch (exact transform on real renderer)"):
		return
	var record: Dictionary = parked.records[index]
	var pose: Transform3D = record.pose
	var original_batch_count := _batch_count_at(pose.origin)
	promoted_id = str(record.source_id)
	var state: Dictionary = await _checkpoint()
	if state.is_empty():
		check(false, "checkpoint before promoted fixture")
		return
	var sequence := int(state.vehicles.get("sequence", 0)) + 1
	state.vehicles.sequence = sequence
	state.vehicles.vehicles.append(_parked_entry(index, 64.0, [2], sequence))
	var reason := str(level.driving.validate_state(state.vehicles))
	if not check(reason.is_empty(), "contract-shaped promoted parked record validates"):
		note("vehicle validation: " + reason)
		return
	promoted_bytes = JSON.stringify(state)
	_fresh_slot(promoted_bytes)
	var result: Dictionary = provider.load_state()
	await frames(3)
	check(result.get("ok", false) and int(result.get("vehicle_fallbacks", -1)) == 0, "promoted parked car restores at its saved pose without fallback")
	var counts := _bodies_by_id()
	var body := _body(promoted_id)
	check(int(counts.get(promoted_id, 0)) == 1 and body != null and body in level.traffic.player_fleet, "exactly one live fleet body owns the promoted source identity")
	if body != null:
		check(str(body.prototype_kind) == str(record.kind) and absf(float(body.health) - 64.0) <= 0.01 and _sorted(body.flat_tires) == [2]
			and body.global_position.distance_to(pose.origin) < 0.1, "promoted body keeps prototype, health, flat tire and pose")
	var current: Dictionary = parked.records[parked.source_index(promoted_id)]
	check(str(current.get("promoted", "")) == promoted_id and current.body.collision_layer == 0 and not _drawn(index),
		"original batch instance and collider hidden exactly once")
	check(_batch_count_at(pose.origin) == original_batch_count - 1, "promotion removes exactly one submitted parked instance")
	var again: Dictionary = provider.load_state()
	await frames(3)
	check(again.get("ok", false) and _bodies_by_id() == counts and _vehicle_set(level.driving.snapshot_state()) == _vehicle_set(state.vehicles),
		"repeated load: same bodies, no duplicated promoted car")
	check(_unique(counts), "no live vehicle identity has two bodies")
	await _changed_geometry(index, state)
	# Promote it again from disk, then prove a pre-vehicle file demotes it.
	_fresh_slot(promoted_bytes)
	var repromoted: Dictionary = provider.load_state()
	await frames(3)
	check(repromoted.get("ok", false) and int(_bodies_by_id().get(promoted_id, 0)) == 1 and not _drawn(index), "promotion restores again from disk after fallbacks")
	_fresh_slot(JSON.stringify(_legacy(3)))
	var legacy: Dictionary = provider.load_state()
	await frames(3)
	current = parked.records[parked.source_index(promoted_id)]
	check(legacy.get("ok", false) and str(current.get("promoted", "")).is_empty() and int(_bodies_by_id().get(promoted_id, 0)) == 0 and _drawn(index)
		and float(current.get("health", 100.0)) == 100.0 and current.get("flat_tires", []).is_empty(),
		"pre-vehicle checkpoint demotes it: repaired original returns to its batch, no orphan body")
	check(_batch_count_at(pose.origin) == original_batch_count, "demotion restores exactly the original submitted instance count")

## Saved spots that no longer fit must fall back explicitly, never silently.
func _changed_geometry(index: int, base: Dictionary) -> void:
	var parked = level.traffic.parked
	var pose: Transform3D = parked.records[index].pose
	var state: Dictionary = base.duplicate(true)
	for entry in state.vehicles.vehicles:
		if str(entry.get("id", "")) == promoted_id:
			# Raised 5 m: no curb record anywhere can match this fingerprint.
			var origin: Array = entry.source_key.origin
			entry.source_key.origin = [float(origin[0]), float(origin[1]) + 5.0, float(origin[2])]
	_fresh_slot(JSON.stringify(state))
	var moved: Dictionary = provider.load_state()
	await frames(3)
	check(moved.get("ok", false) and int(moved.get("vehicle_fallbacks", 0)) >= 1 and int(_bodies_by_id().get(promoted_id, 0)) == 0
		and str(parked.records[index].get("promoted", "")).is_empty() and _drawn(index) and "remembered car" in str(moved.get("reason", ""))
		and int(provider.get_status().last_load.get("vehicle_fallbacks", 0)) >= 1,
		"changed parking layout drops the stale promotion (original stays drawn) with an explicit reported fallback")
	state = base.duplicate(true)
	state.vehicles.vehicles = state.vehicles.vehicles.filter(func(entry): return str(entry.get("id", "")) != promoted_id)
	for entry in state.vehicles.vehicles:
		if str(entry.get("source", "")) == "starter":
			entry.position = [snappedf(pose.origin.x, 0.001), snappedf(pose.origin.y, 0.001), snappedf(pose.origin.z, 0.001)]
			entry.yaw = snappedf(atan2(pose.basis.z.x, pose.basis.z.z), 0.0001)
	_fresh_slot(JSON.stringify(state))
	var blocked: Dictionary = provider.load_state()
	await frames(3)
	var starter: Node3D = level.driving.starter
	check(blocked.get("ok", false) and int(blocked.get("vehicle_fallbacks", 0)) >= 1 and is_instance_valid(starter)
		and starter.global_position.distance_to(pose.origin) > 1.5 and _unique(_bodies_by_id()),
		"starter saved inside a parked car falls back to a checked spot with explicit status")

# --- Corrupt and future records ------------------------------------------------------

func _corrupt_vehicle_records() -> void:
	if not check(vehicle_api and not promoted_bytes.is_empty(), "corrupt vehicle record checks have the API and a promoted fixture"):
		return
	var base: Dictionary = JSON.parse_string(promoted_bytes)
	for kind in ["not_object", "no_version", "fractional_version", "non_finite_position", "duplicate_identity", "tire_out_of_range",
			"duplicate_tire", "health_out_of_range", "disabled_mismatch", "unknown_prototype", "over_bound", "source_claimed_twice",
			"second_promotion_same_source"]:
		var text := _corrupted(base, str(kind))
		var reason: String = provider.validate_snapshot(_parsed(text))
		if not check(not reason.is_empty() and reason != "unsupported version", "corrupt vehicle record rejected as invalid, not future: " + str(kind)):
			continue
		_fresh_slot(text, promoted_bytes)
		var read: Dictionary = provider.read_snapshot()
		check(read.get("ok", false) and read.get("source", "") == "backup" and not provider.get_status().write_blocked,
			str(kind) + ": the older valid backup recovers instead")
		var written: int = provider.write_snapshot(base)
		var preserved: Array = provider.get_status().preserved_files
		check(written == OK and not preserved.is_empty() and FileAccess.get_file_as_string(preserved[-1]) == text,
			str(kind) + ": rejected primary preserved byte for byte before repair")
	var marks := _marks()
	var corrupt := _corrupted(base, "duplicate_identity")
	_fresh_slot(corrupt)
	var refused: Dictionary = provider.load_state()
	check(not refused.get("ok", true) and _untouched(marks) and provider.write_snapshot(base) == ERR_UNAVAILABLE and _bytes(fixture) == corrupt,
		"a sole corrupt vehicle checkpoint is refused, changes nothing and is never overwritten")

func _corrupted(base: Dictionary, kind: String) -> String:
	var state: Dictionary = base.duplicate(true)
	var payload: Dictionary = state.vehicles
	var records: Array = payload.vehicles
	if not payload.get("parked_damage") is Array:
		payload.parked_damage = []
	var promoted: Dictionary = {}
	for entry in records:
		if str(entry.get("source", "")) == "parked":
			promoted = entry
	var first: Dictionary = records[0]
	match kind:
		"not_object":
			state.vehicles = "garage"
		"no_version":
			payload.erase("version")
		"fractional_version":
			payload.version = 1.5
		"non_finite_position":
			first.position = [7777.5, float(first.position[1]), float(first.position[2])]
		"duplicate_identity":
			records.append(first.duplicate(true))
		"tire_out_of_range":
			first.flat_tires = [7]
		"duplicate_tire":
			first.flat_tires = [1, 1]
		"health_out_of_range":
			first.health = 140.0
		"disabled_mismatch":
			first.health = 50.0
			first.disabled = true
		"unknown_prototype":
			first.prototype = "hovercraft"
		"over_bound":
			var parked = level.traffic.parked
			for index in parked.records.size():
				if records.size() > 8:
					break
				if str(parked.records[index].get("source_id", "")) != str(promoted.get("id", "")):
					records.append(_parked_entry(index, 90.0, [], 0))
		"source_claimed_twice":
			payload.parked_damage.append({"source_id": str(promoted.get("source_id", "")), "source_key": canonical(promoted.get("source_key", {})),
				"health": 80.0, "flat_tires": []})
		"second_promotion_same_source":
			var copy: Dictionary = promoted.duplicate(true)
			copy.id = "parked_999"
			records.append(copy)
	var text := JSON.stringify(state)
	return text.replace("7777.5", "1e999") if kind == "non_finite_position" else text

func _future_records() -> void:
	var base: Dictionary = await _checkpoint()
	if not check(not base.is_empty(), "checkpoint for future-record scenarios"):
		return
	var valid := JSON.stringify(base)
	if vehicle_api:
		var declared = level.driving.get("PERSIST_VERSION")
		var future: Dictionary = base.duplicate(true)
		future.vehicles.version = (int(declared) if declared is int else 1) + 1
		var future_text := JSON.stringify(future)
		_expect_protected(future_text, valid, "newer vehicle payload in the checkpoint")
		var marks := _marks()
		_fresh_slot("{truncated", future_text)
		var read: Dictionary = provider.read_snapshot()
		check(not read.get("ok", true) and provider.write_snapshot(base) == ERR_UNAVAILABLE and _bytes(fixture + ".bak") == future_text and _untouched(marks),
			"newer vehicle payload in the backup also blocks rollback and writes")
		_fresh_slot("")
		_write_raw(fixture + ".tmp", future_text)
		read = provider.read_snapshot()
		check(not read.get("ok", true) and provider.write_snapshot(base) == ERR_UNAVAILABLE and _bytes(fixture + ".tmp") == future_text,
			"a newer client's pending vehicle rename is protected before any write")
	for section in ["progression", "inventory", "residents", "deaths"]:
		var nested: Dictionary = base.duplicate(true)
		nested[section].version = 99
		_expect_protected(JSON.stringify(nested), valid, "newer nested %s section" % section)
		# A garbled version is corruption, not a newer build: the backup recovers.
		nested[section].version = "two"
		_fresh_slot(JSON.stringify(nested), valid)
		var garbled: Dictionary = provider.read_snapshot()
		check(garbled.get("ok", false) and garbled.get("source", "") == "backup" and not provider.get_status().write_blocked,
			"garbled nested %s version is recoverable corruption, not a protected future file" % section)
	var container: Dictionary = base.duplicate(true)
	container.version = Save.VERSION + 1
	_expect_protected(JSON.stringify(container), valid, "newer container schema")
	for section in ["container", "progression", "inventory", "residents", "deaths", "vehicles"]:
		for malformed in ["1", "two", null, true, [], {}, 1.5, 0, -1]:
			var corrupt: Dictionary = base.duplicate(true)
			if section == "container":
				corrupt.version = malformed
			else:
				corrupt[section].version = malformed
			_expect_corrupt_backup(corrupt, valid, "%s version %s" % [section, JSON.stringify(malformed)])
	for field in ["health", "weapon", "ammo", "reserve"]:
		for malformed in [null, [], {}, true]:
			var corrupt: Dictionary = base.duplicate(true)
			corrupt.equipment[field] = malformed
			_expect_corrupt_backup(corrupt, valid, "equipment %s %s" % [field, JSON.stringify(malformed)])
	var wrong_chapter: Dictionary = base.duplicate(true)
	wrong_chapter.chapter = 1
	_expect_corrupt_backup(wrong_chapter, valid, "numeric chapter")
	var real: Node = level.driving
	var without := Node3D.new()
	level.driving = without
	var reason: String = provider.validate_snapshot(base)
	level.driving = real
	without.free()
	check(reason == "unsupported version", "a build without vehicle persistence protects schema 4 instead of dropping its cars")

func _expect_corrupt_backup(state: Dictionary, valid: String, label: String) -> void:
	var reason: String = provider.validate_snapshot(state)
	var corrupt := JSON.stringify(state)
	var marks := _marks()
	_fresh_slot(corrupt, valid)
	var read: Dictionary = provider.read_snapshot()
	check(not reason.is_empty() and reason != "unsupported version" and read.get("ok", false)
		and read.get("source", "") == "backup" and not provider.get_status().write_blocked
		and _bytes(fixture) == corrupt and _bytes(fixture + ".bak") == valid and _untouched(marks),
		"corrupt JSON rejects cleanly and recovers backup without coercion or mutation: " + label)

func _expect_protected(primary: String, backup: String, label: String) -> void:
	var marks := _marks()
	_fresh_slot(primary, backup)
	var read: Dictionary = provider.read_snapshot()
	var blocked: bool = provider.get_status().write_blocked
	var written: int = provider.write_snapshot(JSON.parse_string(backup))
	var loaded: Dictionary = provider.load_state()
	check(not read.get("ok", true) and str(read.get("reason", "")) == "unsupported version" and blocked and written == ERR_UNAVAILABLE
		and not loaded.get("ok", true) and _bytes(fixture) == primary and _bytes(fixture + ".bak") == backup and _untouched(marks),
		label + " blocks rollback to the older backup and is never overwritten")

# --- All-or-nothing application (container logic) ---------------------------------

func _transactional_rollback() -> void:
	var real_driving: Node = level.driving
	var stub := DrivingStub.new()
	level.driving = stub
	var state: Dictionary = provider.snapshot_state()
	if not check(not state.is_empty() and int(state.version) == Save.VERSION, "stub-backed schema 4 checkpoint"):
		level.driving = real_driving
		stub.free()
		return
	# The checkpoint differs from the live session in every section it applies.
	state.clock.total_minutes = float(state.clock.total_minutes) + 120.0
	state.progression.money = int(state.progression.money) + 250
	state.equipment.health = 40.0
	state.missions = {"active_id": "lost_satchel", "stage": 1, "completed_ids": [], "score": 0}
	state.vehicles.sequence = 4242
	var text := JSON.stringify(state)
	stub.refuse_preflight = true
	_fresh_slot(text)
	var marks := _marks()
	var refused: Dictionary = provider.load_state()
	check(not refused.get("ok", true) and not refused.get("partial", true) and "vehicles unavailable" in str(refused.get("reason", ""))
		and stub.restores == 0 and stub.resets == 0 and _untouched(marks) and provider.get_status().write_blocked and _bytes(fixture) == text,
		"vehicle preflight refusal applies nothing: clock, wallet, inventory, case, player and cars untouched")
	stub.refuse_preflight = false
	stub.refuse_sequence = 4242
	_fresh_slot(text)
	marks = _marks()
	var rolled: Dictionary = provider.load_state()
	check(not rolled.get("ok", true) and not rolled.get("partial", true) and rolled.get("rollback_clean", false) and stub.restores == 2
		and _untouched(marks) and level.missions.active_id.is_empty() and provider.get_status().write_blocked,
		"vehicle restore failure after preflight rolls back clock, wallet, inventory and player")
	stub.refuse_sequence = -1
	var real_missions: Node = level.missions
	var cases := CaseRestoreFails.new()
	cases.real = real_missions
	level.missions = cases
	_fresh_slot(text)
	marks = _marks()
	var restores := stub.restores
	var undone: Dictionary = provider.load_state()
	var after_cases := _marks()
	level.missions = real_missions
	cases.free()
	check(not undone.get("ok", true) and not undone.get("partial", true) and undone.get("rollback_clean", false) and "case unavailable" in str(undone.get("reason", ""))
		and stub.restores == restores + 2 and int(stub.applied.get("sequence", -1)) == 0 and _same(marks, after_cases),
		"late case failure also returns the already-restored cars to their pre-load state")
	stub.refuse_reset = true
	var legacy_text := JSON.stringify(_legacy(3))
	_fresh_slot(legacy_text)
	marks = _marks()
	var reset_refused: Dictionary = provider.load_state()
	check(not reset_refused.get("ok", true) and reset_refused.get("rollback_clean", false) and not reset_refused.get("partial", true)
		and "reset refused" in str(reset_refused.get("reason", "")) and _untouched(marks)
		and provider.get_status().write_blocked and _bytes(fixture) == legacy_text,
		"legacy vehicle reset false refuses migration, rolls back and protects original bytes")
	var rollback_point: Dictionary = provider._rollback_point()
	rollback_point.vehicles = {}
	check(not provider._rollback(rollback_point), "rollback reports false when its fallback vehicle reset refuses")
	stub.refuse_reset = false
	check(provider._rollback(rollback_point), "older void/null vehicle reset remains compatible during rollback")
	stub.active = true
	_fresh_slot(text)
	marks = _marks()
	var seated: Dictionary = provider.load_state()
	check(not seated.get("ok", true) and not seated.get("partial", true) and _untouched(marks) and not provider.get_status().write_blocked,
		"load while a car is occupied refuses without touching anything or pausing saves")
	stub.active = false
	stub.fallbacks = [{"vehicle_id": "player_starter", "reason": "pose_blocked", "action": "kept_spawn"}]
	_fresh_slot(text)
	var fell: Dictionary = provider.load_state()
	check(fell.get("ok", false) and int(fell.get("vehicle_fallbacks", 0)) == 1 and "remembered car" in str(fell.get("reason", ""))
		and int(provider.get_status().last_load.get("vehicle_fallbacks", 0)) == 1 and not provider.get_status().write_blocked,
		"a car fallback loads with an explicit, reported status (never silent)")
	stub.fallbacks = []
	# Root's startup order: progression set up but not begun, then load_state().
	level.progression.setup(level)
	stub.refuse_sequence = 4242
	_fresh_slot(text)
	var startup: Dictionary = provider.load_state()
	var begun: Dictionary = level.progression.begin_new_game()
	check(not startup.get("ok", true) and begun.get("ok", false), "a refused startup load leaves progression un-begun, so a new game can still start")
	level.driving = real_driving
	stub.free()
	provider._write_blocked = false

func _checkpoint_blocking() -> void:
	_fresh_slot("")
	level.law.wanted = 2
	var wanted: int = provider.save_state()
	var reason: String = provider.checkpoint_blocker()
	level.law.reset_state()
	check(wanted == ERR_BUSY and reason == "police incident in progress" and not FileAccess.file_exists(fixture), "no checkpoint while wanted")
	level.combat.downed = 1.0
	var fighting: int = provider.save_state()
	reason = provider.checkpoint_blocker()
	level.combat.downed = 0.0
	check(fighting == ERR_BUSY and reason == "fight in progress" and not FileAccess.file_exists(fixture), "no checkpoint while downed in a fight")

# --- Fresh scene and cases -------------------------------------------------------------

func _fresh_scene_reload() -> void:
	var expected: Variant = null
	if check(vehicle_api and not promoted_bytes.is_empty(), "fresh-scene vehicle reload has the API and a promoted fixture"):
		_fresh_slot(promoted_bytes)
		provider.load_state()
		await frames(3)
		var state: Dictionary = await _checkpoint()
		if not state.is_empty():
			expected = _vehicle_set(state.vehicles)
			_fresh_slot(JSON.stringify(state))
	if not await _boot():
		return
	if expected == null:
		return
	var result: Dictionary = provider.load_state()
	await frames(3)
	check(result.get("ok", false) and int(result.get("version", 0)) == Save.VERSION and int(result.get("vehicle_fallbacks", -1)) == 0,
		"fresh scene restores schema 4 cars from disk alone without fallback")
	check(_vehicle_set(level.driving.snapshot_state()) == expected, "fresh scene vehicle registry equals the saved one")
	var counts := _bodies_by_id()
	check(_unique(counts) and int(counts.get(promoted_id, 0)) == 1, "one body per remembered identity in the new scene")
	var parked = level.traffic.parked
	var index: int = parked.source_index(promoted_id)
	check(index >= 0 and str(parked.records[index].get("promoted", "")) == promoted_id and parked.records[index].body.collision_layer == 0
		and not _drawn(index), "new scene hides the promoted original exactly once")
	check(level.traffic.vehicles.size() == 90 and level.traffic.player_fleet.size() <= 9, "traffic population intact; remembered fleet bounded")
	var again: Dictionary = provider.load_state()
	await frames(3)
	check(again.get("ok", false) and _bodies_by_id() == counts and _vehicle_set(level.driving.snapshot_state()) == expected,
		"repeated load in the new scene duplicates nothing")

func _active_and_dead_cases() -> void:
	var base: Dictionary = await _checkpoint()
	if not check(not base.is_empty(), "checkpoint for case scenarios"):
		return
	var schema: Dictionary = level.missions.save_schema()
	var impossible: Dictionary = base.duplicate(true)
	impossible.missions = {"active_id": "lost_satchel", "stage": 2, "completed_ids": [], "score": 0}
	impossible.deaths = {"version": 1, "dead": ["resident"]}
	var reason: String = provider.validate_snapshot(impossible)
	var text := JSON.stringify(impossible)
	_fresh_slot(text)
	var marks := _marks()
	var refused: Dictionary = provider.load_state()
	check(reason == "case requires deceased contact" and not refused.get("ok", true) and _untouched(marks) and not level.combat.is_actor_dead("resident")
		and _bytes(fixture) == text, "a file needing its own dead contact is refused whole; nobody dies from a refused load")
	level.combat.restore_deaths({"version": 1, "dead": ["gardener"]})
	var revival: Dictionary = base.duplicate(true)
	revival.missions = {"active_id": "missing_tools", "stage": 0, "completed_ids": [], "score": 0}
	revival.clock.total_minutes = float(base.clock.total_minutes) + 90.0
	_fresh_slot(JSON.stringify(revival))
	marks = _marks()
	var revived: Dictionary = provider.load_state()
	check(not revived.get("ok", true) and not revived.get("partial", true) and "case unavailable" in str(revived.get("reason", ""))
		and level.combat.is_actor_dead("gardener") and not level.npcs.actor_position("gardener").is_finite() and _untouched(marks),
		"a case needing a contact killed this session is refused without resurrecting them")
	var closed: Dictionary = base.duplicate(true)
	closed.missions = {"active_id": "", "stage": 0, "completed_ids": ["missing_tools"], "score": int(schema.missing_tools.reward)}
	closed.deaths = {"version": 1, "dead": ["gardener"]}
	_fresh_slot(JSON.stringify(closed))
	var done: Dictionary = provider.load_state()
	check(done.get("ok", false) and level.missions.completed_ids.has("missing_tools") and int(level.progression.money) == int(base.progression.money)
		and level.combat.is_actor_dead("gardener"), "a completed case survives its contact's death; reconciliation marks it paid without paying")
	var clue_only: Dictionary = base.duplicate(true)
	clue_only.missions = {"active_id": "dumping", "stage": 3, "completed_ids": [], "score": 0}
	clue_only.deaths = {"version": 1, "dead": ["gardener", "lookout", "officer"]}
	_fresh_slot(JSON.stringify(clue_only))
	var resumed: Dictionary = provider.load_state()
	var cash: int = level.progression.money
	var repeat: Dictionary = provider.load_state()
	check(resumed.get("ok", false) and repeat.get("ok", false) and level.missions.active_id == "dumping" and level.missions.stage == 3
		and level.missions.score == 0 and level.combat.is_actor_dead("lookout") and level.combat.is_actor_dead("officer") and int(level.progression.money) == cash,
		"a clue-only stage resumes beside dead past contacts; a repeated load pays nothing")

# --- Helpers -------------------------------------------------------------------------

func _checkpoint() -> Dictionary:
	for attempt in 300:
		var state: Dictionary = provider.snapshot_state()
		if not state.is_empty():
			return state
		await frames(1)
	note("checkpoint blocked: " + str(provider.blocked_reason))
	return {}

func _stand(at: Vector3) -> void:
	level.player.global_position = at
	level.player.velocity = Vector3.ZERO
	level.player.current_speed = 0.0
	level.player.reset_jump()
	level.player.update_camera()
	level.traffic._update_presence()

func _marks() -> Dictionary:
	return {"minutes": level.world_time.total_minutes, "money": int(level.progression.money), "health": level.combat.health,
		"inventory": canonical(level.combat.equipment_snapshot()), "player": level.player.global_position,
		"missions": canonical(level.missions.snapshot_state()),
		"vehicles": canonical(level.driving.snapshot_state()) if level.driving.has_method("snapshot_state") else null}

func _same(before: Dictionary, after: Dictionary) -> bool:
	return (is_equal_approx(float(after.minutes), float(before.minutes)) and after.money == before.money and is_equal_approx(float(after.health), float(before.health))
		and after.inventory == before.inventory and Vector3(after.player).distance_to(Vector3(before.player)) < 0.01 and after.missions == before.missions
		and after.vehicles == before.vehicles)

func _untouched(before: Dictionary) -> bool:
	return _same(before, _marks())

func _vehicle_record(payload, id: String) -> Dictionary:
	if payload is Dictionary and payload.get("vehicles") is Array:
		for entry in payload.vehicles:
			if entry is Dictionary and str(entry.get("id", "")) == id:
				return entry
	return {}

## Order-insensitive canonical payload: list order is not part of the contract.
func _vehicle_set(payload) -> Variant:
	var copy: Variant = canonical(payload)
	if copy is Dictionary:
		for key in ["vehicles", "parked_damage"]:
			if copy.get(key) is Array:
				copy[key].sort_custom(func(a, b): return str(a.get("id", a.get("source_id", ""))) < str(b.get("id", b.get("source_id", ""))))
	return copy

## Pose, damage and source per remembered identity (sequence counters excluded).
func _semantics(payload) -> Dictionary:
	var out := {}
	if not payload is Dictionary:
		return out
	for entry in payload.get("vehicles", []):
		var at: Array = entry.get("position", [0, 0, 0])
		out[str(entry.get("id", ""))] = {"x": snappedf(float(at[0]), 0.01), "y": snappedf(float(at[1]), 0.01), "z": snappedf(float(at[2]), 0.01),
			"yaw": snappedf(float(entry.get("yaw", 0.0)), 0.001), "health": snappedf(float(entry.get("health", 100.0)), 0.1),
			"flats": _sorted(entry.get("flat_tires", [])), "source": str(entry.get("source_id", ""))}
	var damage = payload.get("parked_damage", [])
	out["parked_damage"] = damage.size() if damage is Array else -1
	return out

func _bodies_by_id() -> Dictionary:
	var counts := {}
	for node in level.find_children("*", "", true, false):
		if node.get_script() == VehicleScript and not node.is_queued_for_deletion():
			var id := str(node.vehicle_id)
			counts[id] = int(counts.get(id, 0)) + 1
	return counts

func _body(id: String) -> Node3D:
	for node in level.find_children("*", "", true, false):
		if node.get_script() == VehicleScript and not node.is_queued_for_deletion() and str(node.vehicle_id) == id:
			return node
	return null

func _unique(counts: Dictionary) -> bool:
	for id in counts:
		if int(counts[id]) != 1:
			note("duplicate live vehicle identity " + str(id))
			return false
	return true

## Same evidence as the session fixture, with the record made near: an exactly
## placed visible batch instance, or the record's own visible damage model.
func _drawn(index: int) -> bool:
	var parked = level.traffic.parked
	var record: Dictionary = parked.records[index]
	var pose: Transform3D = record.pose
	parked.set_presence(pose.origin)
	var visible: bool = record.has("damage_model") and is_instance_valid(record.damage_model) and record.damage_model.visible
	if DisplayServer.get_name() == "headless":
		# Dummy rendering does not retain instance transforms. Require every batch
		# count to match the complete source roster, plus +/-1 deltas around the
		# real promotion above. Real rendering keeps the exact-transform gate below.
		var expected := {}
		for source in parked.records:
			if int(source.presence) > 0 and str(source.get("promoted", "")).is_empty() and not source.has("damage_model"):
				var key := str(source.kind) + ("_near" if int(source.presence) == 2 else "_far")
				expected[key] = int(expected.get(key, 0)) + 1
		var counts_match := true
		for key in parked._batches:
			counts_match = counts_match and parked._batches[key].multimesh.visible_instance_count == int(expected.get(key, 0))
		check(counts_match, "dummy batch submitted counts equal the complete unpromoted source roster")
		visible = counts_match and (visible or (int(record.presence) > 0 and str(record.get("promoted", "")).is_empty() and not record.has("damage_model")))
		parked.set_presence(level.player.global_position)
		return visible
	for batch in parked._batches.values():
		var count: int = batch.multimesh.visible_instance_count
		if count < 0:
			count = batch.multimesh.instance_count
		for slot in count:
			visible = visible or batch.multimesh.get_instance_transform(slot).is_equal_approx(pose)
	parked.set_presence(level.player.global_position)
	return visible

func _batch_count_at(center: Vector3) -> int:
	var parked = level.traffic.parked
	parked.set_presence(center)
	var count := 0
	for batch in parked._batches.values():
		count += batch.multimesh.visible_instance_count
	parked.set_presence(level.player.global_position)
	return count

func _quiet_parked_index() -> int:
	var parked = level.traffic.parked
	var starter: Node3D = level.driving.starter
	for index in parked.records.size():
		var record: Dictionary = parked.records[index]
		if not str(record.get("promoted", "")).is_empty() or float(record.get("health", 100.0)) < 100.0 or not record.get("flat_tires", []).is_empty():
			continue
		var at: Vector3 = record.pose.origin
		if at.distance_to(level.player.global_position) < 30.0 or (is_instance_valid(starter) and at.distance_to(starter.global_position) < 30.0):
			continue
		if _drawn(index):
			return index
	return -1

## A remembered parked car exactly as vehicle-contract.md section 5 describes it.
func _parked_entry(index: int, health: float, flats: Array, last_used: int) -> Dictionary:
	var record: Dictionary = level.traffic.parked.records[index]
	var pose: Transform3D = record.pose
	var key = record.get("source_key", {})
	if not key is Dictionary or key.is_empty():
		key = {"street": str(record.street), "kind": str(record.kind), "origin": [pose.origin.x, pose.origin.y, pose.origin.z]}
	return {"id": str(record.source_id), "source": "parked", "source_id": str(record.source_id), "source_key": canonical(key),
		"prototype": str(record.kind), "paint": int(record.paint),
		"position": [snappedf(pose.origin.x, 0.001), snappedf(pose.origin.y, 0.001), snappedf(pose.origin.z, 0.001)],
		"yaw": snappedf(atan2(pose.basis.z.x, pose.basis.z.z), 0.0001), "health": snappedf(health, 0.01), "disabled": health <= 0.0,
		"flat_tires": flats.duplicate(), "last_used": last_used}

static func _sorted(value) -> Array:
	var out: Array = []
	if value is Array:
		for entry in value:
			out.append(int(entry))
	out.sort()
	return out

static func _vec(value) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2])) if value is Array and value.size() == 3 else Vector3.INF

func _bytes(target: String) -> String:
	return FileAccess.get_file_as_string(target) if FileAccess.file_exists(target) else ""

func _write_raw(target: String, contents: String) -> void:
	var file := FileAccess.open(target, FileAccess.WRITE)
	file.store_string(contents)
	file.close()

func _fresh_slot(primary: String, backup := "") -> void:
	provider._write_blocked = false
	_cleanup()
	if not primary.is_empty():
		_write_raw(fixture, primary)
	if not backup.is_empty():
		_write_raw(fixture + ".bak", backup)

func _cleanup() -> void:
	# Only this fixture basename in its explicit project directory, no recursion.
	if fixture.is_empty() or not DirAccess.dir_exists_absolute(fixture.get_base_dir()):
		return
	for filename in DirAccess.get_files_at(fixture.get_base_dir()):
		if filename == fixture.get_file() or filename.begins_with(fixture.get_file() + "."):
			DirAccess.remove_absolute(fixture.get_base_dir().path_join(filename))

func _finish() -> void:
	if finished:
		return
	finished = true
	if is_instance_valid(level) and level.get("driving") != null and level.driving.has_method("clear_control_override"):
		level.driving.clear_control_override()
	print("[world_persistence] %d passed, %d failed" % [passes, failures])
	get_tree().quit(1 if failures else 0)
