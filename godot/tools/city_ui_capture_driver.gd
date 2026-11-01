extends Node
## Bounded engine-only captures. Never takes desktop screenshots or captures host input.
const T := preload("res://scripts/ui/hud_theme.gd")
const OUTPUT := "res://../artifacts/pen-lucy-streets"
var level: Node3D
var failed := false
var finished := false
var results: Dictionary = {}

func _ready() -> void:
	_run.call_deferred()
	_watchdog()

func _watchdog() -> void:
	await get_tree().create_timer(180.0, true, false, true).timeout
	if not finished:
		push_error("[ui_capture] bounded 180-second capture deadline exceeded")
		get_tree().quit(1)

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
		await get_tree().physics_frame

func require(value: bool, label: String) -> bool:
	print("[ui_capture] %s %s" % ["PASS" if value else "FAIL", label])
	results[label] = value
	failed = failed or not value
	return value

func capture(filename: String) -> void:
	await frames(5)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	require(image.get_size() == Vector2i(1280, 720), filename + " has exact 1280x720 pixels")
	var error := image.save_png(OUTPUT.path_join(filename + ".png"))
	require(error == OK, "save " + filename)
	require(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, filename + " leaves host pointer visible")

func _run() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if not require("--offscreen-validation" in args, "explicit offscreen validation flag supplied"):
		_finish()
		return
	var workspace := ProjectSettings.globalize_path("res://..").simplify_path().replace("\\", "/")
	var profile := OS.get_user_data_dir().replace("\\", "/")
	if not require(profile.to_lower().begins_with((workspace + "/.work/test-profile/").to_lower()), "profile isolated under project .work/test-profile"):
		_finish()
		return
	if not require(DisplayServer.get_name() != "headless", "GPU viewport available for engine PNGs"):
		_finish()
		return
	# The invocation must already begin offscreen. Keep it windowed and unfocusable
	# before any city load, and never request foreground or OS pointer capture.
	var window := get_tree().root
	window.unfocusable = true
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_position(Vector2i(-10000, -10000))
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_size = Vector2i(1280, 720)
	window.content_scale_factor = 1.0
	window.size = Vector2i(1280, 720)
	window.scaling_3d_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	for i in 1800:
		await frames(1)
		level = get_tree().current_scene
		if level != null and level.get("level_ready") == true:
			break
	if not require(level != null and level.get("level_ready") == true, "neighborhood initialized within frame budget"):
		_finish()
		return
	require(level.offscreen_validation, "level honors validation mode")
	level._settings.values.master = 0.0
	level._settings.apply_settings(false, "master")
	level.resume_exploring()
	await frames(30)
	for kind in ["display", "body500", "body600", "body700", "mono", "monob"]:
		T.font(kind)
		require(bool(T._real.get(kind, false)), "original bundled font " + kind)
	level._build_loading_screen()
	await capture("ui-loading")
	level._loading.queue_free()
	level._loading = null
	level._loading_status = null
	await frames(2)
	await capture("ui-ledger")
	if require(level.player.request_jump(), "grounded player accepts jump for isolated engine capture"):
		await frames(8)
		await capture("player-jump")
		for i in 180:
			await frames(1)
			if level.player.is_on_floor():
				break
		require(level.player.is_on_floor(), "player lands before UI captures")
	var original_score: int = level.missions.score
	var ambient: Dictionary = level.conversations.get("officer", {})
	if require(not ambient.is_empty() and level.open_conversation(ambient), "actual registered officer ambient dialogue opens"):
		await capture("ui-ambient-dialogue")
		level._dialogue.close()
	# Locate a clear real approach to the resident, rather than bypassing mission range checks.
	level.pause_exploring()
	var resident: Vector3 = level.npcs.actor_position("resident")
	var approach_found := false
	for offset in [Vector3(0, 0, 1.7), Vector3(1.7, 0, 0), Vector3(0, 0, -1.7), Vector3(-1.7, 0, 0)]:
		var placement: Dictionary = level.npcs.find_safe_position(resident + offset, 0.28)
		if not bool(placement.get("ok", false)):
			continue
		level._place_player(placement.position, atan2(-offset.x, -offset.z))
		await frames(3)
		if level.missions._can_interact(resident):
			approach_found = true
			break
	level.resume_exploring()
	if require(approach_found and level.interact(), "real resident E interaction opens case offer"):
		require(level.missions.active_id.is_empty(), "case offer is read-only")
		await capture("ui-case-offer")
		level._dialogue.state.choose(0)
		require(level.missions.active_id == "lost_satchel" and level.missions.stage == 0, "explicit choice starts case at stage zero")
		if require(level.interact(), "real case interaction opens authored step"):
			require(level._dialogue.state.current().text == level.missions._steps[0].dialogue, "case dialogue is exact authored text")
			await capture("ui-case-dialogue")
			level._dialogue.close()
		require(level.missions.stage == 0 and level.missions.score == original_score, "capture/open/close cannot advance or award rewards")
		# Deliberately confirm the introductory step, then capture a longer real
		# destination route to the clue on both maps. This is an explicit action.
		if require(level.interact(), "introductory step can reopen for explicit confirmation"):
			level._dialogue.state.choose(0)
			require(level.missions.stage == 1 and level.mission_navigation.route.size() >= 2, "confirmed case updates yellow route to clue")
			var geographic_builds: int = level._radar.map.geography.build_count
			await capture("ui-mission-minimap")
			level.toggle_map()
			await capture("ui-mission-map")
			level.resume_exploring()
			require(level._radar.map.geography.build_count == geographic_builds, "mission route leaves static minimap geography cached")
	level.missions.cancel_case()
	require(level.mission_navigation.route.is_empty() and level.mission_navigation.active_id.is_empty(), "cancel removes yellow route and destination")
	# A longer accepted case from the normal spawn makes the yellow street
	# guidance legible beyond the short satchel approach.
	level.spawn_player()
	if require(level.start_neighborhood_case("missing_tools"), "accept longer garden-tools case from normal spawn"):
		await frames(3)
		var route_length := 0.0
		var path: PackedVector3Array = level.mission_navigation.route
		for i in range(1, path.size()):
			route_length += path[i - 1].distance_to(path[i])
		require(route_length >= 45.0, "garden-tools route visibly spans at least 45 metres")
		await capture("ui-long-mission-minimap")
		level.toggle_map()
		await capture("ui-long-mission-map")
		var destination: Vector3 = level.mission_navigation.target
		level._map_overlay.map.zoom_by(2.5)
		level._map_overlay.map.map_center = Vector2((level.player.position.x + destination.x) * 0.5, (level.player.position.z + destination.z) * 0.5)
		await capture("ui-long-mission-map-zoom")
		level.resume_exploring()
	level.missions.cancel_case()
	level._map_overlay.map.fit_neighborhood()
	level.pause_exploring()
	await capture("ui-settings")
	var settings_tabs: TabContainer = level._settings.find_children("*", "TabContainer", true, false)[0]
	settings_tabs.current_tab = 1
	await capture("ui-settings-audio")
	settings_tabs.current_tab = 2
	await capture("ui-settings-controls")
	settings_tabs.current_tab = 0
	level.resume_exploring()
	level.toggle_map()
	await capture("ui-map")
	_finish()

func _finish() -> void:
	if finished:
		return
	finished = true
	var report := FileAccess.open(OUTPUT.path_join("ui-capture-report.json"), FileAccess.WRITE)
	if report:
		report.store_string(JSON.stringify({"failed": failed, "checks": results}, "\t"))
	get_tree().quit(1 if failed else 0)
