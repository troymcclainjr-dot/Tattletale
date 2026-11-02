extends "res://tests/city_priorities_session_fixture.gd"
## Real Settings callbacks, root load guard, complete world snapshot and file
## selection. Never opens the personal save slot.
func _run() -> void:
	if not await boot_world():
		_finish()
		return
	output_dir = ProjectSettings.globalize_path("res://../.work/next-five-20261101/settings-checkpoint-" + run_id)
	DirAccess.make_dir_recursive_absolute(output_dir)
	fixture = output_dir.path_join("checkpoint.json")
	provider.path = fixture
	_cleanup()
	await frames(30)
	level.pause_exploring()
	var settings: Control = level._settings
	settings.show()
	settings.refresh_checkpoint_status()
	await frames(4)
	begin_phase("first-save-menu")
	check(level.offscreen_validation and provider.path != Save.DEFAULT_PATH, "actual menu uses only a private checkpoint provider")
	check(not provider.has_checkpoint_candidates() and settings._load_button.disabled, "empty private slot disables Load")
	check(provider.checkpoint_blocker().is_empty(), "actual player is safe to checkpoint before menu save")
	var save_button: Button
	for button in settings.find_children("*", "Button", true, false):
		if button.text == "Save progress":
			save_button = button
			break
	check(save_button != null, "real Save progress button exists")
	if save_button == null:
		_finish()
		return
	await click(save_button)
	await frames(3)
	_record_menu_state("after_first_save", settings)
	check(FileAccess.file_exists(fixture) and not settings._load_button.disabled, "first real Save enables Load without closing Settings")
	check(settings.visible and level.paused, "same Settings menu remains open after save")
	check(settings._save_feedback.text == "Progress saved.", "exact save feedback survives button refresh")
	if not FileAccess.file_exists(fixture):
		_finish()
		return
	var bytes := FileAccess.get_file_as_string(fixture)
	begin_phase("temporary-only-recovery")
	check(DirAccess.rename_absolute(fixture, fixture + ".tmp") == OK, "arrange a completed temporary checkpoint awaiting its final rename")
	check(not FileAccess.file_exists(fixture) and not FileAccess.file_exists(fixture + ".bak"), "temporary is the sole candidate")
	var previous_result: String = provider.last_result
	var previous_load: Dictionary = provider.last_load.duplicate(true)
	var previous_block: bool = provider._write_blocked
	settings.refresh_checkpoint_status()
	check(provider.has_checkpoint_candidates() and not settings._load_button.disabled, "temporary-only checkpoint enables Load in Settings")
	check(provider._write_blocked == previous_block and provider.last_result == previous_result and provider.last_load == previous_load and FileAccess.get_file_as_string(fixture + ".tmp") == bytes, "availability refresh changes no protection, load state or checkpoint bytes")
	await click(settings._load_button)
	await frames(3)
	check(settings._load_confirmation != null and settings._load_confirmation.visible and settings._load_confirmation.is_embedded(), "real Load button opens normal embedded confirmation")
	if settings._load_confirmation == null:
		_finish()
		return
	if not await _confirm_embedded(settings._load_confirmation, "load", settings):
		_finish()
		return
	await frames(6)
	_record_menu_state("after_load", settings)
	check(bool(provider.last_load.get("ok", false)) and str(provider.last_load.get("source", "")) == "temporary", "normal root load guard and provider restore the sole temporary checkpoint")
	check(settings._save_feedback.text == provider.last_result and settings.visible and level.paused, "load feedback and open paused menu survive refresh")
	check(not settings._load_button.disabled and FileAccess.get_file_as_string(fixture + ".tmp") == bytes, "load keeps temporary checkpoint available and byte-identical")
	begin_phase("refusal-and-recovery-refresh")
	# Exercise the existing protection barrier using only this private provider.
	provider._write_blocked = true
	settings.refresh_checkpoint_status()
	await click(save_button)
	await frames(2)
	_record_menu_state("after_refused_save", settings)
	check(provider._write_blocked and not FileAccess.file_exists(fixture) and FileAccess.get_file_as_string(fixture + ".tmp") == bytes, "refused Save cannot overwrite protected temporary candidate")
	check(settings._recover_button.visible and not settings._load_button.disabled and settings._save_feedback.text == Save.WRITE_BLOCKED, "refused Save refresh preserves protection controls and exact failure feedback")
	await click(settings._recover_button)
	await frames(3)
	_record_menu_state("recovery_open", settings)
	check(settings._recover_confirmation != null and settings._recover_confirmation.visible and settings._recover_confirmation.is_embedded(), "Recover still requires its normal explicit embedded confirmation")
	if settings._recover_confirmation != null:
		if not await _confirm_embedded(settings._recover_confirmation, "recovery", settings):
			_finish()
			return
		await frames(5)
		_record_menu_state("after_recovery", settings)
		check(not provider._write_blocked and FileAccess.file_exists(fixture), "confirmed recovery preserves old candidate and writes current private checkpoint")
		var old_preserved := false
		for path in provider._preserved_files:
			if str(path).begins_with(fixture + ".tmp.recovery-"):
				old_preserved = FileAccess.get_file_as_string(path) == bytes
		check(old_preserved, "recover keeps exact temporary bytes in recovery archive")
		check(not settings._recover_button.visible and not settings._load_button.disabled and settings._save_feedback.text == provider.last_result, "recovery refresh updates both controls without replacing success feedback")
	provider.enabled = false
	settings.refresh_checkpoint_status("Fixture disabled")
	check(settings._load_button.disabled and settings._save_feedback.text == "Fixture disabled", "disabled provider still blocks Load even when candidates exist")
	result_details.scope = "Real Settings controls, root load, private full world files; first save, temporary-only load, read-only availability, protected save refusal and explicit recovery."
	_finish()

func _record_menu_state(label: String, settings: Control) -> void:
	var focus := get_viewport().gui_get_focus_owner()
	var state := {"feedback": str(settings._save_feedback.text), "last_result": str(provider.last_result),
		"last_load": provider.last_load.duplicate(true), "write_blocked": bool(provider._write_blocked),
		"load_disabled": bool(settings._load_button.disabled), "recover_visible": bool(settings._recover_button.visible),
		"settings_visible": settings.is_visible_in_tree(), "paused": bool(level.paused),
		"load_dialog_visible": settings._load_confirmation != null and settings._load_confirmation.visible,
		"recovery_dialog_visible": settings._recover_confirmation != null and settings._recover_confirmation.visible,
		"root_focus": str(focus.get_path()) if focus != null else ""}
	result_details[label] = state
	print("[settings_checkpoint] ", label, " ", JSON.stringify(state))

func _confirm_embedded(dialog: ConfirmationDialog, label: String, settings: Control) -> bool:
	# The generic click helper has no embedded-window routing contract. Confirm
	# using real Enter events on the dialog's separate input surface, with its
	# authored affirmative button focused. Never emit confirmed.
	var confirmations: Array[bool] = []
	dialog.confirmed.connect(func(): confirmations.append(true), CONNECT_ONE_SHOT)
	dialog.get_ok_button().grab_focus()
	await get_tree().process_frame
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ENTER
		event.physical_keycode = KEY_ENTER
		event.pressed = pressed
		dialog.push_input(event, true)
		await get_tree().process_frame
	await frames(2)
	_record_menu_state(label + "_confirmed", settings)
	result_details[label + "_confirmed_count"] = confirmations.size()
	var confirmed := confirmations.size() == 1 and not dialog.visible
	check(confirmed, label + " affirmative Enter invokes exactly one real confirmation and closes dialog")
	return confirmed
