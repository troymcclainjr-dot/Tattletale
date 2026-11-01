extends Node
## Copied into the isolated export stage only; never installed in the source game.
const PlayMode := preload("res://scripts/city/city_play_mode.gd")
const RELEASE_INCIDENT_SOURCE := "external:release_smoke"
var report := {"checks": {}, "passed": false}
var destination := ""
var phase := ""
var nonce := ""
var finished := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--priorities-release-phase="):
			phase = argument.trim_prefix("--priorities-release-phase=")
		elif argument.begins_with("--priorities-release-report="):
			destination = argument.trim_prefix("--priorities-release-report=")
		elif argument.begins_with("--priorities-release-nonce="):
			nonce = argument.trim_prefix("--priorities-release-nonce=")
	if phase.is_empty():
		queue_free()
		return
	if phase == "startup":
		# This setting must have applied before native window creation, not only
		# via the root Window assignment below. The private install owns it.
		_check(ProjectSettings.get_setting("display/window/size/no_focus", false) == true, "startup_project_no_focus")
		if not report.checks.startup_project_no_focus:
			get_tree().quit(1)
			return
	# This autoload exists only in the isolated export stage and runs before the
	# main scene. Keep a real display for normal automatic save loading, but no
	# on-screen window/focus/cursor ownership. A disclosed stage-only pointer
	# guard also prevents capture if Godot's focus cache is stale.
	get_tree().root.unfocusable = true
	if phase == "startup":
		get_tree().root.position = Vector2i(-10000, -10000)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_run.call_deferred()
	_watchdog()

func _check(value: bool, label: String) -> void:
	report.checks[label] = value
	print("[priorities_release] %s %s" % ["PASS" if value else "FAIL", label])

func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _watchdog() -> void:
	await get_tree().create_timer(220.0, true, false, true).timeout
	if not finished:
		_check(false, "watchdog")
		_finish()

func _run() -> void:
	var level: Node
	for i in 3000:
		level = get_tree().current_scene
		if level != null and bool(level.get("ready_to_play")):
			break
		await _frames(1)
	_check(level != null and bool(level.get("ready_to_play")), "world_ready")
	if not report.checks.world_ready:
		_finish()
		return
	if phase == "startup":
		# Observe before pausing: the stage guard must already have kept capture
		# off through ordinary startup. This pause cannot mask a failed guard.
		report.startup_mouse_before_pause = Input.mouse_mode
		_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "startup_guard_kept_mouse_visible")
		level.pause_exploring()
	report.phase = phase
	report.nonce = nonce
	report.main_scene = level.scene_file_path
	report.user_data_dir = OS.get_user_data_dir()
	report.executable = OS.get_executable_path()
	report.runtime_pid = OS.get_process_id()
	report.editor = OS.has_feature("editor")
	report.debug = OS.is_debug_build()
	report.display_server = DisplayServer.get_name()
	report.offscreen_validation = bool(level.offscreen_validation)
	_check(not report.editor and not report.debug, "release_template")
	_check(level.scene_file_path == "res://scenes/city/pen_lucy.tscn", "main_scene")
	_check(level.npcs.crowd.residents.size() == 1200 and level.residents.actors.size() == 40, "population")
	_check(Assets.used_placeholder.is_empty(), "no_placeholders")
	_check(level.get("inspector") != null, "inspector_present")
	var resources: Array[String] = []
	_list_resources("res://", resources)
	report.resource_files = resources
	var credits := FileAccess.get_file_as_string("res://assets/data/release_notices.txt")
	_check("OpenStreetMap" in credits and "ODbL" in credits and "Bungee" in credits and "Barlow" in credits and "Courier" in credits, "packed_credits")
	var fonts = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fonts/SOURCES.json"))
	var fonts_ok: bool = fonts is Array and not fonts.is_empty()
	if fonts is Array:
		for font in fonts:
			var path := "res://assets/fonts/" + str(font.file)
			if path.ends_with(".ttf"):
				fonts_ok = fonts_ok and ResourceLoader.exists(path) and load(path) != null
			else:
				fonts_ok = fonts_ok and FileAccess.get_sha256(path) == str(font.sha256)
	_check(fonts_ok, "packed_fonts_and_licenses")
	if not _foundation_ready(level):
		_finish()
		return
	var save: Node = level.world_save
	# Normal offscreen runs intentionally suppress saving. This private probe
	# opts in for API phases only. Startup phase observes the ordinary level load
	# before making any provider mutation, and never calls load_state itself.
	if phase != "startup":
		save.enabled = true
	report.save_path = ProjectSettings.globalize_path(save.path)
	report.settings_path = ProjectSettings.globalize_path(level._settings.SAVE_PATH)
	if phase == "fresh":
		_check(not FileAccess.file_exists(save.path), "fresh_save_absent")
		_check(not FileAccess.file_exists(level._settings.SAVE_PATH), "fresh_settings_absent")
		level.resume_exploring()
		await _frames(20)
		var start: Vector3 = level.player.global_position
		Input.action_press("move_forward")
		await _frames(30)
		Input.action_release("move_forward")
		await _frames(20)
		report.movement_metres = start.distance_to(level.player.global_position)
		_check(report.movement_metres > 0.1, "input_moves_player")
		var before := int(level.progression.money)
		var credited: int = level.progression.credit(7, "release smoke")
		_check(credited == 7 and level.progression.money == before + 7, "production_progression_transaction")
		level._settings._change("fps_cap", 60)
		level._settings._change("fov", 79.0)
		# Persist the test profile's windowed preference through the normal UI
		# settings API. Restore reapplies settings after initial setup; a saved
		# Maximized value would move this hidden test window back onto a monitor.
		level._settings._change("display", "Windowed")
		_check(is_equal_approx(level.player.camera_fov, 79.0), "settings_apply")
		# Explicit persistence fixture through production APIs, not a claim of
		# completing a case or witnessing an incident through gameplay input.
		if not _seed_foundation_state(level):
			_finish()
			return
		for i in 600:
			if save.can_checkpoint():
				break
			await _frames(1)
		_check(save.can_checkpoint() and save.save_state() == OK, "production_save")
		var written: Dictionary = save.read_snapshot()
		_check_foundation_checkpoint(level, written)
	elif phase == "reload":
		_check(FileAccess.file_exists(save.path), "reload_save_present")
		var expected: Dictionary = save.read_snapshot()
		var restored: Dictionary = save.load_state()
		_check(bool(restored.get("ok", false)) and not bool(restored.get("partial", true)), "production_reload")
		_check(bool(expected.get("ok", false)) and int(expected.get("state", {}).get("progression", {}).get("money", -1)) == int(level.progression.money), "progression_restored")
		_check(is_equal_approx(level._settings.values.fov, 79.0) and is_equal_approx(level.player.camera_fov, 79.0) and level._settings.values.display == "Windowed", "settings_loaded_on_startup")
		_check_foundation_checkpoint(level, expected)
	elif phase == "startup":
		report.startup_window = _window_receipt()
		_check(report.startup_window.outside_all_screens and report.startup_window.unfocusable,
			"startup_private_window")
		_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "startup_mouse_uncaptured")
		report.save_enabled_at_startup = bool(save.enabled)
		report.startup_load = save.last_load.duplicate(true)
		_check(DisplayServer.get_name() != "headless" and not bool(level.offscreen_validation)
			and not OS.get_cmdline_user_args().has("--offscreen-validation"), "normal_startup_mode")
		_check(report.save_enabled_at_startup, "save_enabled_by_startup")
		_check(bool(report.startup_load.get("ok", false)) and not bool(report.startup_load.get("partial", true)), "automatic_world_restore")
		_check(FileAccess.file_exists(save.path), "startup_save_present")
		# read_snapshot is read-only; the already-restored live values must match.
		var expected: Dictionary = save.read_snapshot()
		var state: Dictionary = expected.get("state", {})
		_check(bool(expected.get("ok", false)) and int(state.get("progression", {}).get("money", -1)) == int(level.progression.money), "startup_progression_restored")
		var clock: Dictionary = state.get("clock", {})
		_check(bool(expected.get("ok", false)) and absf(float(clock.get("total_minutes", -1000.0)) - float(level.world_time.total_minutes)) < 1.0
			and absf(float(clock.get("elapsed_seconds", -1000.0)) - float(level.world_time.elapsed_seconds)) < 2.0, "startup_clock_restored")
		_check(is_equal_approx(level._settings.values.fov, 79.0) and is_equal_approx(level.player.camera_fov, 79.0) and level._settings.values.display == "Windowed", "settings_loaded_on_startup")
		_check_foundation_checkpoint(level, expected)
	else:
		_check(false, "known_phase")
	report.money = level.progression.money
	report.fov = level._settings.values.fov
	report.save_sha256 = FileAccess.get_sha256(save.path)
	if phase != "startup":
		save.enabled = false
	_finish()

func _has_methods(object: Object, names: Array) -> bool:
	if object == null:
		return false
	for method in names:
		if not object.has_method(str(method)):
			return false
	return true

func _foundation_ready(level: Node) -> bool:
	var phone: Node = level.player.get("phone")
	var bike: Node = level.get("bicycle")
	var incidents: Node = level.get("incidents")
	var missions: Node = level.missions
	var policy: bool = not PlayMode.player_combat_enabled() and not PlayMode.player_driving_enabled() and not PlayMode.alignment_enabled()
	policy = policy and level.combat.has_method("player_offense_enabled") and not level.combat.player_offense_enabled()
	_check(policy, "pacifist_policy")
	report.play_mode = PlayMode.status()
	var services := _has_methods(phone, ["get_status", "build_photo_context", "register_photo_subject_provider"])
	services = services and _has_methods(bike, ["get_status", "is_crashed", "blocks_checkpoint"])
	services = services and _has_methods(incidents, ["snapshot_state", "validate_state", "restore_state", "open_incident", "resolve_incident", "get_incident"])
	services = services and _has_methods(missions, ["snapshot_state", "validate_state", "restore_state", "case_library_report", "case_library_errors", "case_detail", "evidence_list"])
	_check(services, "foundation_services")
	if not services:
		return false
	var phone_status: Dictionary = phone.get_status()
	var bike_status: Dictionary = bike.get_status()
	_check(phone_status.has("page") and phone_status.has("captures_emitted") and phone_status.has("gallery_limit")
		and bike_status.get("kind") == "bicycle" and bike_status.has("crashed") and bike_status.has("crash_phase"), "phone_bicycle_schema")
	var wired: bool = phone.has_signal("photo_captured") and phone.has_signal("police_requested") and incidents.has_signal("incident_changed") and bike.has_signal("pedestrian_contact")
	if wired:
		wired = phone.photo_captured.is_connected(Callable(level, "_on_phone_photo_captured")) \
			and phone.police_requested.is_connected(Callable(level, "_request_police_help")) \
			and incidents.incident_changed.is_connected(Callable(missions, "on_incident_event")) \
			and bike.pedestrian_contact.is_connected(Callable(level, "_on_bicycle_contact"))
	_check(wired, "foundation_bridges")
	var library: Dictionary = missions.case_library_report()
	report.case_library = library
	_check(missions.case_library_errors().is_empty() and "parcel_report" in library.get("cases", [])
		and not library.get("templates", []).is_empty() and _packed_case_files(), "packed_case_library")
	var incident_state: Dictionary = incidents.snapshot_state()
	var mission_state: Dictionary = missions.snapshot_state()
	var engine: Dictionary = mission_state.get("case_engine", {})
	_check(int(incident_state.get("version", 0)) == 1 and incidents.validate_state(incident_state).is_empty()
		and int(engine.get("version", 0)) == 1 and missions.validate_state(mission_state, {"progression": level.progression.snapshot_state(), "deaths": level.combat.death_snapshot()}).is_empty(), "foundation_schema")
	return not report.checks.values().has(false)

func _packed_case_files() -> bool:
	var base := "res://assets/data/cases/"
	var index: Variant = JSON.parse_string(FileAccess.get_file_as_string(base + "index.json"))
	if not index is Dictionary or int(index.get("schema", 0)) != 1:
		return false
	var files: Array[String] = [base + "index.json"]
	for section in ["templates", "cases"]:
		var entries: Variant = index.get(section)
		if not entries is Array or entries.is_empty():
			return false
		for relative in entries:
			if not relative is String or relative.is_absolute_path() or ".." in relative or not relative.ends_with(".json"):
				return false
			var path: String = base + relative
			if not FileAccess.file_exists(path):
				return false
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if not data is Dictionary or int(data.get("schema", 0)) != 1:
				return false
			files.append(path)
	report.packed_case_files = files
	return files.has(base + "parcel_report.json")

func _seed_foundation_state(level: Node) -> bool:
	# Exercise the supported old-save migration path: stage 2 has an examined
	# parcel but no new case-engine section. The live provider creates its real
	# active record and labels reconstructed evidence as migrated.
	var legacy: Dictionary = level.missions.snapshot_state().duplicate(true)
	legacy.erase("case_engine")
	legacy.active_id = "parcel_report"
	legacy.stage = 2
	var valid: bool = level.missions.validate_state(legacy).is_empty()
	var migrated: bool = valid and level.missions.restore_state(legacy)
	var mission_state: Dictionary = level.missions.snapshot_state()
	var engine: Dictionary = mission_state.get("case_engine", {})
	var active: Dictionary = engine.get("active", {})
	var evidence: Array = active.get("evidence", [])
	var at: Vector3 = level.player.global_position
	# A closed external record tests nonempty durable data without dispatching
	# police, fabricating a photo, altering custody or claiming a witnessed act.
	var opened: Dictionary = level.incidents.open_incident({"template": "case", "source": RELEASE_INCIDENT_SOURCE,
		"offender_id": "crowd_0", "at": at, "title": "Release persistence fixture"})
	var closed: bool = bool(opened.get("ok", false)) and level.incidents.resolve_incident(str(opened.get("incident_id", "")), "no_threat", "Isolated release API fixture")
	var created: bool = migrated and active.get("id") == "parcel_report" and int(active.get("stage", -1)) == 2 and not evidence.is_empty() and closed
	_check(created, "foundation_fixture_created")
	report.persistence_fixture = {"kind": "synthetic production API / legacy migration fixture",
		"case_id": "parcel_report", "stage": 2, "migrated_evidence_count": evidence.size(),
		"incident_id": str(opened.get("incident_id", "")), "gameplay_completion_claimed": false}
	return created

func _release_incident(section: Dictionary) -> Dictionary:
	for entry in section.get("incidents", []):
		if entry is Dictionary and entry.get("source") == RELEASE_INCIDENT_SOURCE:
			return entry
	return {}

func _canonical(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))

func _check_foundation_checkpoint(level: Node, read: Dictionary) -> void:
	var state: Dictionary = read.get("state", {})
	var mission_state: Dictionary = state.get("missions", {})
	var engine: Dictionary = mission_state.get("case_engine", {})
	var active: Dictionary = engine.get("active", {})
	var incident_state: Dictionary = state.get("incidents", {})
	var incident := _release_incident(incident_state)
	var checkpoint_ok: bool = bool(read.get("ok", false)) and int(engine.get("version", 0)) == 1 \
		and active.get("id") == "parcel_report" and int(active.get("stage", -1)) == 2 and not active.get("evidence", []).is_empty() \
		and int(incident_state.get("version", 0)) == 1 and incident.get("state") == "resolved" \
		and incident.get("resolution", {}).get("outcome") == "no_threat"
	_check(checkpoint_ok, "foundation_checkpoint")
	var live_missions: Dictionary = level.missions.snapshot_state()
	var live_incidents: Dictionary = level.incidents.snapshot_state()
	var restored: bool = checkpoint_ok and _canonical(live_missions.get("case_engine", {})) == _canonical(engine) \
		and live_missions.get("active_id") == mission_state.get("active_id") and live_missions.get("stage") == mission_state.get("stage") \
		and _canonical(_release_incident(live_incidents)) == _canonical(incident)
	_check(restored, "foundation_restore")
	report.foundation_checkpoint = {"case_engine_version": engine.get("version", 0), "case_id": active.get("id", ""),
		"case_stage": active.get("stage", -1), "evidence_count": active.get("evidence", []).size(),
		"incident_version": incident_state.get("version", 0), "incident_id": incident.get("id", ""),
		"incident_state": incident.get("state", ""), "matches_live": restored}

func _window_receipt() -> Dictionary:
	# Include decorations: a title bar on any monitor is still desktop exposure.
	var rect := Rect2i(DisplayServer.window_get_position_with_decorations(), DisplayServer.window_get_size_with_decorations())
	var screens: Array = []
	var outside := rect.size.x > 0 and rect.size.y > 0 and DisplayServer.get_screen_count() > 0
	for index in DisplayServer.get_screen_count():
		var screen := Rect2i(DisplayServer.screen_get_position(index), DisplayServer.screen_get_size(index))
		screens.append([screen.position.x, screen.position.y, screen.size.x, screen.size.y])
		outside = outside and not rect.intersects(screen)
	return {"outside_all_screens": outside, "unfocusable": get_tree().root.unfocusable,
		"focused": get_tree().root.has_focus(), "mouse_mode": Input.mouse_mode,
		"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "screen_rects": screens}

func _list_resources(directory: String, output: Array[String]) -> void:
	for filename in DirAccess.get_files_at(directory):
		output.append(directory.path_join(filename))
	for child in DirAccess.get_directories_at(directory):
		_list_resources(directory.path_join(child), output)

func _finish() -> void:
	if finished:
		return
	finished = true
	Input.action_release("move_forward")
	report.passed = not report.checks.is_empty() and not report.checks.values().has(false)
	var output := FileAccess.open(destination, FileAccess.WRITE)
	if output == null:
		get_tree().quit(2)
		return
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	get_tree().quit(0 if report.passed else 2)
