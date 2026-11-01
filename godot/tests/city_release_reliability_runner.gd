extends Node
var failures := 0
var _finished := false
const FIXTURE := "res://../.work/alive-next/exit-fixture.json"
func check(ok: bool, label: String) -> void:
	print("[release_reliability] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok: failures += 1
func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
		await get_tree().physics_frame
func _ready() -> void:
	_run.call_deferred()
	_watchdog()
func _watchdog() -> void:
	await get_tree().create_timer(150.0, true, false, true).timeout
	if not _finished:
		check(false, "reliability fixture watchdog")
		_finish()
func _run() -> void:
	check(_cleanup(), "fixture starts without its previous checkpoint/recovery files")
	get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	await frames(4)
	var level: Node = get_tree().current_scene
	for i in 700:
		if level != null and level.get("level_ready") == true: break
		await frames(1)
		level = get_tree().current_scene
	if level == null or level.get("level_ready") != true:
		check(false, "level initialized")
		_finish()
		return
	level.pause_exploring()
	var settings: Control = level._settings
	settings.values.fov = 82.0
	settings.apply_settings(false, "fov")
	check(is_equal_approx(level.player.camera_fov, 82.0), "FOV preference applies to production camera")
	settings.values.fov = 400.0
	settings._sanitize()
	check(settings.values.fov == 90.0, "FOV configuration bounded")
	settings.values.fov = 68.0
	settings.apply_settings(false, "fov")
	var cases: Node3D = level.missions
	check(not cases.get_status().all_complete, "new neighborhood has available case work")
	for definition in cases.CASES:
		cases.completed_ids[definition.id] = true
		cases.score += int(definition.reward)
	var status: Dictionary = cases.get_status()
	check(status.all_complete and status.offers.is_empty() and "All neighborhood cases resolved" in status.objective, "last case replaces misleading offer objective")
	level._update_ui()
	check("All neighborhood cases resolved" in level._objective.text and "community points" in level._distance.text, "completion is visible in normal ledger")
	cases.completed_ids.clear()
	cases.score = 0
	# Isolated provider path: even a regression cannot overwrite the user's save.
	var save: Node = level.world_save
	save.setup(level, ProjectSettings.globalize_path(FIXTURE))
	save._write_blocked = true
	level._update_ui()
	check(level._save_warning.visible, "blocked saving has a persistent gameplay indicator")
	level._request_exit(true)
	check(level._exit_confirmation != null and level._exit_confirmation.visible and get_tree().current_scene == level, "failed save blocks scene exit until explicit confirmation")
	check("could not be restored" in level._exit_confirmation.dialog_text and "Recover saving" in level.save_progress(), "blocked incompatible save has accurate recovery feedback")
	level._exit_confirmation.hide()
	save._write_blocked = false
	level.player.impact_recovery = 1.0
	level._request_exit(false)
	check(level._exit_confirmation.visible and "solid ground" in level._exit_confirmation.dialog_text and not level._exit_to_menu, "unstable checkpoint blocks window close with a recoverable explanation")
	level._exit_confirmation.hide()
	level.player.impact_recovery = 0.0
	level._exit_confirmation.canceled.emit()
	check(get_tree().current_scene == level and level.paused, "cancel retains the world and paused settings")
	var rejected := "{\"version\":999,\"sentinel\":\"keep these original bytes\"}"
	var old := FileAccess.open(save.path, FileAccess.WRITE)
	old.store_string(rejected)
	old.close()
	save._write_blocked = true
	var recovered: Error = save.recover_saving()
	check(recovered == OK and not save._write_blocked and save.read_snapshot().ok, "explicit recovery creates a usable current checkpoint")
	var preserved := false
	for path in save.get_status().preserved_files:
		preserved = preserved or FileAccess.get_file_as_string(path) == rejected
	check(preserved, "recovery preserves rejected checkpoint byte for byte")
	level._update_ui()
	check(not level._save_warning.visible and save.get_status().age_seconds >= 0, "recovery clears persistent warning and records checkpoint age")
	level._notice.text = ""
	level._notice_queue.clear()
	level.show_notice("First event")
	level.show_notice("Second event")
	level.show_notice("Third event")
	check(level._notice.text == "First event" and level._notice_queue == ["Second event", "Third event"], "simultaneous notices retain readable FIFO order")
	save.enabled = false
	_finish()

func _cleanup() -> bool:
	# Enumerate only files with this fixture's exact basename in this fixed
	# project-owned directory. No recursive removal and no user:// paths.
	var fixture := ProjectSettings.globalize_path(FIXTURE).simplify_path()
	var directory := fixture.get_base_dir()
	var basename := fixture.get_file()
	if not DirAccess.dir_exists_absolute(directory):
		return true
	var okay := true
	for filename in DirAccess.get_files_at(directory):
		if filename == basename or filename.begins_with(basename + "."):
			var target := directory.path_join(filename).simplify_path()
			if target.get_base_dir() != directory:
				return false
			okay = DirAccess.remove_absolute(target) == OK and okay
	return okay

func _finish() -> void:
	if _finished:
		return
	_finished = true
	var current: Node = get_tree().current_scene
	if current != null and current.get("world_save") != null:
		current.world_save.enabled = false
	check(_cleanup(), "fixture removes only its checkpoint and recovery files")
	get_tree().quit(1 if failures else 0)
