extends Node
## Isolated file-lifecycle test. No user slot and no playable world are opened.
const Save := preload("res://scripts/city/city_world_save.gd")
class ArchiveFixture extends Save:
	var fixture_blocker := ""
	func checkpoint_blocker() -> String:
		return fixture_blocker


# Exercise the actual root callback and provider guard without building the city.
class CallbackHost extends "res://scripts/city/pen_lucy_level.gd":
	var marker_refreshes := 0
	func _ready() -> void: pass
	func _exit_tree() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func _update_markers() -> void: marker_refreshes += 1
	func _apply_shop_cosmetics() -> void: pass
class CallbackSave extends Save:
	var loads := 0
	func load_state() -> Dictionary:
		loads += 1
		return {"ok": true, "reason": "Backup checkpoint loaded; bicycle placement could not be verified."}
	func safe_player_position(at: Vector3) -> Dictionary:
		return {"position": at}
class CallbackPlayer extends CharacterBody3D:
	var impact_recovery := 0.0
class CallbackResidents extends Node3D:
	func get_status() -> Dictionary: return {"pending_routes": 0}
class CallbackCombat extends Node3D:
	var state := {"active_count": 0, "knocked_count": 0, "downed": 0.0, "combo": 0, "reloading": false}
	func get_status() -> Dictionary: return state
class CallbackIncidents extends Node:
	var transition := false
	func blocks_checkpoint() -> bool: return transition
class CallbackStreaming extends Node:
	var refreshes := 0
	func refresh_now() -> void: refreshes += 1
class CallbackBasketball extends Node3D:
	var _notice := "Pickup game rules already delivered as a notice."
	func interaction_prompt() -> String:
		return "PICKUP 0–0\nYour ball\nShot power 50% · release LMB\n" + _notice

var failures := 0
var passes := 0
var directory := ""
var created: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	print("[fresh_start] %s %s" % ["PASS" if ok else "FAIL", description])
	passes += int(ok)
	failures += int(not ok)

func provider(name_: String) -> ArchiveFixture:
	var save := ArchiveFixture.new()
	add_child(save)
	save.path = directory.path_join(name_ + ".json")
	save.enabled = true
	return save

func write(path: String, bytes: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(bytes)
	file.close()
	created.append(path)
	return true

func seed_candidates(save: ArchiveFixture) -> Dictionary:
	var bytes := {save.path: "primary: incompatible bytes kept verbatim\n", save.path + ".bak": "backup: previous checkpoint\n", save.path + ".tmp": "temporary: interrupted write\n"}
	for path in bytes:
		check(write(path, bytes[path]), "fixture candidate written: " + str(path).get_file())
	return bytes

func same_files(bytes: Dictionary) -> bool:
	for path in bytes:
		if not FileAccess.file_exists(path) or FileAccess.get_file_as_string(path) != bytes[path]:
			return false
	return true

func queue(save: ArchiveFixture) -> void:
	save._pending = {"source": "manual", "waiting_for": "a safe stop", "attempts": 0, "error": ERR_BUSY, "queued": true}

func _run() -> void:
	await _load_callback()
	directory = ProjectSettings.globalize_path("res://../.work/next-five-20261101/fresh-start-%d" % OS.get_process_id())
	if not check_directory():
		_finish()
		return
	var save := provider("preserve")
	var bytes := seed_candidates(save)
	queue(save)
	var notifications: Array[Dictionary] = []
	save.pending_save_resolved.connect(func(result: Dictionary): notifications.append(result))
	check(save.archive_for_fresh_start() == OK, "safe fresh start archives all candidates")
	check(not save.enabled and save._pending.is_empty(), "saving stays disabled until reload and pending request is discarded")
	check(notifications.size() == 1 and notifications[0].state == "cancelled", "queued save receives exactly one cancellation")
	check(save._preserved_files.size() == 3, "primary, backup and temporary each have a recovery copy")
	var preserved := true
	for source in bytes:
		var found := false
		for archived in save._preserved_files:
			if archived.begins_with(source + ".fresh-"):
				created.append(archived)
				found = FileAccess.file_exists(archived) and FileAccess.get_file_as_string(archived) == bytes[source]
		preserved = preserved and found and not FileAccess.file_exists(source)
	check(preserved, "archives retain every byte and original candidate names are absent")
	var archive_count := save._preserved_files.size()
	check(save.archive_for_fresh_start() == ERR_UNAVAILABLE and save._preserved_files.size() == archive_count, "second click cannot archive again before reload")
	var unsafe := provider("unsafe")
	var unsafe_bytes := seed_candidates(unsafe)
	queue(unsafe)
	unsafe.fixture_blocker = "recovering from a bicycle crash"
	check(unsafe.archive_for_fresh_start() == ERR_BUSY and same_files(unsafe_bytes) and unsafe._preserved_files.is_empty(), "unsafe start changes none of the candidate bytes")
	check(unsafe.enabled and not unsafe._pending.is_empty(), "unsafe refusal keeps saving and queued request intact")
	var disabled := provider("disabled")
	var disabled_bytes := seed_candidates(disabled)
	queue(disabled)
	disabled.enabled = false
	check(disabled.archive_for_fresh_start() == ERR_UNAVAILABLE and same_files(disabled_bytes) and disabled._preserved_files.is_empty(), "unavailable session changes none of the candidate bytes")
	check(not disabled._pending.is_empty(), "unavailable refusal does not cancel an existing queue")
	# Windows normally refuses renaming an open backup. The primary has already
	# moved by then, so this safely exercises partial-rename rollback. Platforms
	# allowing open-file rename still have to preserve the successful result.
	var locked := provider("locked")
	var locked_bytes := seed_candidates(locked)
	queue(locked)
	var handle := FileAccess.open(locked.path + ".bak", FileAccess.READ)
	check(handle != null, "backup lock fixture opens")
	if handle != null:
		var locked_result := locked.archive_for_fresh_start()
		handle.close()
		if locked_result != OK:
			check(same_files(locked_bytes) and locked._preserved_files.is_empty(), "failed backup rename rolls the already-moved primary back byte-for-byte")
			check(locked.enabled and not locked._write_blocked and not locked._pending.is_empty(), "successful rename rollback preserves the live visit and queued save")
		else:
			var lock_preserved := locked._preserved_files.size() == 3
			for archived in locked._preserved_files:
				created.append(archived)
				lock_preserved = lock_preserved and FileAccess.file_exists(archived)
			check(lock_preserved and not locked.enabled, "platform allows open-file rename: all recovery copies still exist")
	var empty := provider("empty")
	check(empty.archive_for_fresh_start() == OK and empty._preserved_files.is_empty() and not empty.enabled, "fresh start without any checkpoint is valid and disables outgoing autosaves")
	_finish()

func _load_callback() -> void:
	var host := CallbackHost.new()
	add_child(host)
	host.player = CallbackPlayer.new()
	host.residents = CallbackResidents.new()
	host.world_time = Node.new()
	host.missions = Node3D.new()
	var combat_ := CallbackCombat.new()
	host.combat = combat_
	var incidents_ := CallbackIncidents.new()
	host.incidents = incidents_
	var streaming_ := CallbackStreaming.new()
	host.streaming = streaming_
	var save := CallbackSave.new()
	host.world_save = save
	save.level = host
	save.enabled = true
	for child in [host.player, host.residents, host.world_time, host.missions, combat_, incidents_, streaming_, save]:
		host.add_child(child)
	combat_.state.active_count = 1
	check(host.load_checkpoint().contains("fight in progress") and save.loads == 0, "actual root load callback refuses active combat before calling load_state")
	combat_.state.active_count = 0
	combat_.state.downed = 2.0
	check(host.load_checkpoint().contains("fight in progress") and save.loads == 0, "actual root load callback refuses a downed player before loading")
	combat_.state.downed = 0.0
	incidents_.transition = true
	check(host.load_checkpoint().contains("incident transition") and save.loads == 0, "actual root load callback refuses an incident transition before loading")
	incidents_.transition = false
	var warning := host.load_checkpoint()
	check(save.loads == 1 and warning == "Backup checkpoint loaded; bicycle placement could not be verified.", "stable root callback loads once and retains fallback warnings verbatim")
	check(host.marker_refreshes == 1 and streaming_.refreshes == 1, "successful root callback refreshes world presentation once")
	host._sandbox_label = Label.new()
	host.add_child(host._sandbox_label)
	host._notice = Label.new()
	host._notice.text = "Unrelated dispatch notice"
	host.add_child(host._notice)
	host.basketball = CallbackBasketball.new()
	host.add_child(host.basketball)
	host._notice_queue.append(host.basketball._notice)
	host._update_sandbox_ui()
	check(host._sandbox_label.text == "PICKUP 0–0\nYour ball\nShot power 50% · release LMB", "basketball HUD retains score possession and charge controls without duplicate activity notice")
	check(host._notice.text == "Unrelated dispatch notice", "basketball HUD does not replace other notices")
	host._notice_queue.clear()
	host._update_sandbox_ui()
	check(host._sandbox_label.text.contains(host.basketball._notice), "unannounced basketball feedback remains visible")
	host.queue_free()
	await get_tree().process_frame

func check_directory() -> bool:
	var result := DirAccess.make_dir_recursive_absolute(directory)
	check(result == OK, "project-local fixture directory is available")
	return result == OK

func _finish() -> void:
	# Delete only exact files this runner created or received as archive results.
	for path in created:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	print("[fresh_start] %d passed; %d failed" % [passes, failures])
	get_tree().quit(0 if failures == 0 else 1)
