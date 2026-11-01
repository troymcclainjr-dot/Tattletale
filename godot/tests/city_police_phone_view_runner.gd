extends Node
## Police page review captures (root-run, graphical offscreen only): the real
## phone page fed with display-only dispatch/record states at 1600x900 and
## 1280x720 — nothing reported yet, a live call being handled with an earlier
## closed one, a queued call, a report shown as interrupted after a reload, and
## a refused call. Checks that the handset, the dispatch line and the report
## button stay on screen and that no card text shows an ETA or progress figure.
## It never captures, warps or releases the desktop pointer.
const Explorer = preload("res://scripts/city/city_player.gd")
const Phone = preload("res://scripts/city/city_player_phone.gd")
const Combat = preload("res://scripts/city/city_combat.gd")
const WorldTime = preload("res://scripts/city/city_world_time.gd")
const WINDOWS := [Vector2i(1600, 900), Vector2i(1280, 720)]
const FORBIDDEN_PROGRESS := ["%", "ETA", "minutes away", "seconds", "progress"]
var failures := 0
var checks: Array[Dictionary] = []
var captures: Array[Dictionary] = []
var output := ""

class PoliceStub extends Node:
	var revision := 1
	var generation := 0
	var view: Dictionary = {}
	func dispatch_view() -> Dictionary:
		return view.duplicate(true)

class IncidentsStub extends Node:
	var revision := 1
	var records: Array = []
	var preview: Dictionary = {"kind": "area_check"}
	func reports_for(_person := "player", limit := 4) -> Array:
		return records.slice(0, limit)
	func phone_report_preview(_at: Vector3) -> Dictionary:
		return preview.duplicate(true)

class LevelFixture extends Node3D:
	var player: CharacterBody3D
	var combat: Node3D
	var ready_to_play := true
	var paused := false
	var offscreen_validation := true
	var inspector: Node
	var world_time: Node
	var missions: Node
	var bicycle: Node
	var npcs: Node
	var police_assistance: Node
	var incidents: Node
	var _ui: CanvasLayer
	func save_progress() -> String:
		return "Progress saved."
	func _nearest_street(_at: Vector3) -> String:
		return "Old York Road"

func _ready() -> void:
	get_tree().root.unfocusable = true
	for singleton in ["G", "Hud"]:
		var node := get_node_or_null("/root/" + singleton)
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED
			if node is CanvasItem or node is CanvasLayer:
				node.hide()
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks.append({"ok": ok, "description": label})
	print("[police_phone_view] %s %s" % ["PASS" if ok else "FAIL", label])
	failures += int(not ok)

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not "--offscreen-validation" in OS.get_cmdline_user_args():
		push_error("Police phone-view captures require a graphical renderer and --offscreen-validation.")
		get_tree().quit(2)
		return
	output = ProjectSettings.globalize_path("res://../.work/five-priorities-20261101/police-phone-view")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-out="):
			output = arg.trim_prefix("--review-out=")
	DirAccess.make_dir_recursive_absolute(output)
	var pointer := Input.mouse_mode
	var level := _world()
	var dispatch := PoliceStub.new()
	level.add_child(dispatch)
	level.police_assistance = dispatch
	var records := IncidentsStub.new()
	level.add_child(records)
	level.incidents = records
	var phone := Phone.new()
	level.add_child(phone)
	phone.setup(level, level.player)
	phone.storage_directory = "user://phone_gallery_test_police_view_%d" % Time.get_ticks_usec()
	await frames(3)
	phone.open()
	for window_size in WINDOWS:
		get_window().size = window_size
		await frames(4)
		for state in _states():
			dispatch.view = state.view
			dispatch.revision += 1
			records.records = state.records
			records.preview = state.preview
			records.revision += 1
			phone.set_report_status(str(state.notice))
			phone.show_page("police")
			await frames(4)
			_review(phone, "%dx%d %s" % [window_size.x, window_size.y, state.name])
			_capture("police-%dx%d-%s" % [window_size.x, window_size.y, state.name], {"state": state.name,
				"cards": phone.get_status().police_cards.size()})
	phone.suspend()
	DirAccess.remove_absolute(phone.storage_directory)
	check(Input.mouse_mode == pointer, "review never changes the desktop pointer mode")
	var file := FileAccess.open(output.path_join("review.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures": failures, "checks": checks, "captures": captures}, "\t"))
	file.close()
	print("[police_phone_view] ", checks.size() - failures, " passed, ", failures, " failed; ", output)
	get_tree().quit(0 if failures == 0 else 1)

## Display-only states. Times are game minutes; nothing here dispatches anyone.
func _states() -> Array:
	var handled := {"id": "incident_4", "ref": "inc_000012", "phone": false, "stage": "handling", "handling": "warning", "outcome": "",
		"message": "The officer issued a warning.", "street": "Old York Road", "threat": "infraction", "responders": {"foot": 1, "cars": 0},
		"suspects": [{"id": "crowd_31", "state": "cited"}], "opened_minutes": 1052.0, "updated_minutes": 1055.0, "closing": false,
		"timeline": [{"stage": "received", "minutes": 1052.0}, {"stage": "dispatched", "minutes": 1052.0}, {"stage": "en_route", "minutes": 1052.5},
			{"stage": "on_scene", "minutes": 1053.5}, {"stage": "handling", "handling": "contact", "minutes": 1054.0},
			{"stage": "handling", "handling": "warning", "minutes": 1055.0}]}
	var reported := {"id": "inc_000012", "title": "Jaywalking", "street": "Old York Road", "state": "responding", "source": "world",
		"report": {"by": "neighbor_w", "minutes": 1052.0, "corroborating": ["player"], "status": "on_scene"}, "resolution": {}, "updated_minutes": 1055.0}
	var earlier := {"id": "incident_2", "ref": "", "phone": true, "stage": "resolved", "handling": "", "outcome": "no_threat",
		"message": "Officers checked the area. Nobody there needed help.", "street": "Rosedale Street", "threat": "none",
		"responders": {"foot": 0, "cars": 0}, "suspects": [], "opened_minutes": 1010.0, "updated_minutes": 1016.0, "closing": true,
		"timeline": [{"stage": "received", "minutes": 1010.0}, {"stage": "dispatched", "minutes": 1010.0}, {"stage": "on_scene", "minutes": 1013.0},
			{"stage": "resolved", "outcome": "no_threat", "minutes": 1016.0}]}
	var queued := {"id": "incident_5", "ref": "", "phone": true, "stage": "queued", "handling": "", "outcome": "",
		"message": "Dispatch got your call. No officer can get there yet; dispatch will keep trying.", "street": "Old York Road", "threat": "none",
		"responders": {"foot": 0, "cars": 0}, "suspects": [], "opened_minutes": 1061.0, "updated_minutes": 1061.0, "closing": false,
		"timeline": [{"stage": "queued", "minutes": 1061.0}]}
	var interrupted := {"id": "inc_000009", "title": "Lost satchel", "street": "Old York Road", "state": "resolved", "source": "world",
		"report": {"by": "player", "minutes": 990.0, "corroborating": []},
		"resolution": {"outcome": "interrupted", "minutes": 995.0, "text": "The response stopped before officers finished, so its result is unknown."}}
	var refusal := {"id": "refusal_1", "stage": "unavailable", "text": "All officers are already on calls. Try again shortly.",
		"street": "Old York Road", "minutes": 1070.0}
	return [
		{"name": "empty", "view": {}, "records": [], "preview": {"kind": "area_check"}, "notice": Phone.DEFAULT_REPORT_STATUS},
		{"name": "handling", "view": {"live": [handled], "history": [earlier], "refusals": []}, "records": [reported],
			"preview": {"kind": "incident", "incident_id": "inc_000012", "title": "Jaywalking", "street": "Old York Road", "already_reported": true, "yours": true},
			"notice": "The officer issued a warning."},
		{"name": "queued", "view": {"live": [queued], "history": [], "refusals": []}, "records": [], "preview": {"kind": "area_check"},
			"notice": str(queued.message)},
		{"name": "after-reload", "view": {"live": [], "history": [], "refusals": []}, "records": [interrupted], "preview": {"kind": "area_check"},
			"notice": Phone.DEFAULT_REPORT_STATUS},
		{"name": "refused", "view": {"live": [], "history": [], "refusals": [refusal]}, "records": [], "preview": {"kind": "area_check"},
			"notice": str(refusal.text)}]

func _review(phone: Node, label: String) -> void:
	var layout: Dictionary = phone.get_status().layout
	var visible_rect := Rect2(Vector2.ZERO, layout.viewport)
	check(visible_rect.grow(0.5).encloses(layout.handset), label + ": handset fits the window")
	var screen: Rect2 = layout.screen
	var first_card: Control = null
	var button: Control = null
	for child in phone._content.get_children():
		if first_card == null and child is PanelContainer:
			first_card = child
		if button == null and child is Button and child.has_meta("police_report_kind"):
			button = child
	check(first_card != null and screen.grow(0.5).encloses(first_card.get_global_rect()), label + ": the dispatch line is on the screen")
	check(button != null and screen.grow(0.5).encloses(button.get_global_rect()) and button.size.y >= 44.0, label + ": the report button is a full-size target on the screen")
	var clean := true
	for text_label in phone._content.find_children("*", "Label", true, false):
		for forbidden in FORBIDDEN_PROGRESS:
			clean = clean and not str(text_label.text).contains(forbidden)
	check(clean, label + ": no ETA or progress figure anywhere on the page")

func _capture(label: String, details: Dictionary) -> void:
	var image := get_viewport().get_texture().get_image()
	var path := output.path_join(label + ".png")
	var ok := image != null and not image.is_empty() and image.save_png(path) == OK
	check(ok, label + " capture saved")
	var record := details.duplicate()
	record["file"] = path
	record["size"] = [image.get_width(), image.get_height()] if image != null else []
	captures.append(record)

func _world() -> LevelFixture:
	var level := LevelFixture.new()
	add_child(level)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("8fb3c9")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.8, 0.8, 0.8)
	level.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0)
	level.add_child(sun)
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	shape.shape = box
	shape.position.y = -.5
	floor.add_child(shape)
	level.add_child(floor)
	level._ui = CanvasLayer.new()
	level.add_child(level._ui)
	level.world_time = WorldTime.new()
	level.add_child(level.world_time)
	level.world_time.set_time(17 * 60 + 42, 2)
	level.player = Explorer.new()
	level.add_child(level.player)
	level.player.enabled = true
	level.player.position = Vector3(0, .05, 0)
	level.combat = Combat.new()
	level.add_child(level.combat)
	level.combat.setup(level)
	level.player.camera_yaw = 0.0
	level.player.camera_pitch = 0.0
	return level
