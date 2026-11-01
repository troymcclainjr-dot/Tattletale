extends Node3D
## In-world handset: neighborhood contacts, camera, private gallery, cases and
## police calls. Menus/dialogue retain higher priority and suspend it; the
## world keeps simulating while it is raised.
signal photo_saved(result: Dictionary)
## Trusted evidence hook: emitted once per stored photo with the live-world
## pose, game time and line-of-sight subjects (see city_photo_context.gd).
signal photo_captured(context: Dictionary)
signal police_requested(world_position: Vector3)
const Gallery := preload("res://scripts/city/city_phone_gallery.gd")
const UI := preload("res://scripts/city/city_phone_ui.gd")
const PhotoContext := preload("res://scripts/city/city_photo_context.gd")
const PoliceStatus := preload("res://scripts/city/city_police_status.gd")
const T := preload("res://scripts/ui/hud_theme.gd")
const VIEWMODEL_LAYER := 1 << 19
const DEFAULT_REPORT_STATUS := "Report nearby violence to neighborhood officers."
## The same police notice is not repeated on the HUD within this window.
const NOTICE_REPEAT_MS := 5000
const PHOTO_DIRECTORY := Gallery.DIRECTORY
const PAGES := ["home", "contacts", "camera", "photos", "photo", "cases", "police"]
const TITLES := {"contacts": "Contacts", "photos": "Photos", "photo": "Photo", "cases": "Cases", "police": "Police"}
const GLYPHS := {"contacts": ["contact", Color("70e0da")], "photos": ["photos", Color("e4b47c")], "photo": ["photos", Color("e4b47c")],
	"cases": ["cases", Color("dda6d1")], "police": ["police", Color("7cbcff")]}
const THUMB_EDGE := 160
var level: Node3D
var player: CharacterBody3D
var active := false
var capturing := false
var photo_fov := 58.0
var photos_taken := 0
var captures_emitted := 0
var last_photo: Dictionary = {}
var last_error := ""
var storage_directory := PHOTO_DIRECTORY
var gallery := Gallery.new()
var page := "home"
var _selected_photo := ""
var _content: VBoxContainer
var _controls: Label
var _previous_mouse_mode: int = Input.MOUSE_MODE_CAPTURED
var _last_police_call := -10000
var _report_status := DEFAULT_REPORT_STATUS
## Police generation the last notice belongs to (-1: no police service).
var _report_generation := -1
## Banner and HUD notices actually shown (identical repeats are not).
var notices_shown := 0
var _police_cards: Array = []
var _police_key := ""
var _hud_notice := ""
var _hud_notice_at := -100000
var _viewmodel: Node3D
var _overlay: CanvasLayer
var _root: Control
var _handset: Control
var _viewfinder: Control
var _scroll: ScrollContainer
var _status_time: Label
var _status_day: Label
var _banner: Control
var _feedback: Label
var _header: Control
var _header_icon: Control
var _header_title: Label
var _hud: CanvasLayer
var _hud_was_visible := true
var _generation := 0
var _feedback_time := 0.0
var _status_refresh := 0.0
var _thumbs: Dictionary = {}
var _providers: Array[Callable] = []

func setup(owner_level: Node3D, owner_player: CharacterBody3D) -> void:
	name = "PlayerPhone"
	level = owner_level
	player = owner_player
	player.phone = self
	_hud = level.get("_ui") as CanvasLayer
	_build_viewmodel()
	_build_overlay()
	gallery.directory = storage_directory
	gallery.reload()
	if is_inside_tree():
		get_viewport().size_changed.connect(_apply_layout)
	set_process(false)

func can_open() -> bool:
	if not is_instance_valid(player) or not bool(level.get("ready_to_play")) or bool(level.get("paused")) or get_tree().paused:
		return false
	if not player.enabled or player.impact_recovery > 0.0 or not player.camera_override.is_empty():
		return false
	if player.has_method("is_seated") and player.is_seated():
		return false
	var bicycle: Node = level.get("bicycle")
	if bicycle != null and bool(bicycle.get("active")):
		return false
	var inspector: Node = level.get("inspector")
	if inspector != null and bool(inspector.get("active")):
		return false
	var combat: Node = player.combat
	return combat == null or (float(combat.get("downed")) <= 0.0 and int(combat.get("combo")) == 0 and float(combat.get("reloading")) <= 0.0)

func open() -> bool:
	if active or not can_open():
		return false
	_previous_mouse_mode = Input.mouse_mode
	active = true
	_generation += 1
	photo_fov = 58.0
	player.reset_jump()
	player.set_orbiting(false)
	player.current_speed = 0.0
	if player.combat != null:
		player.combat.aiming = false
	if _hud != null:
		_hud_was_visible = _hud.visible
		_hud.hide()
	_viewmodel.show()
	_overlay.show()
	_notice("")
	_apply_layout()
	_refresh_status_bar()
	set_process(true)
	player.update_camera()
	show_page("home")
	return true

func close() -> void:
	suspend()
	_set_pointer_mode(_previous_mouse_mode)

func _set_pointer_mode(mode: int) -> void:
	# Validation must never capture, release, warp, or otherwise own the desktop
	# cursor. Rendering a photo does not require a mouse-mode change.
	if DisplayServer.get_name() == "headless" or (level != null and bool(level.get("offscreen_validation"))):
		return
	Input.mouse_mode = mode

func suspend() -> void:
	if not active and not capturing:
		return
	active = false
	_generation += 1
	_release_focus()
	_viewmodel.hide()
	_overlay.hide()
	if _hud != null:
		_hud.visible = _hud_was_visible
	set_process(false)
	# Do not set player.enabled, pause state, mouse capture or camera mode here.
	# The menu/dialogue owner may already have changed them deliberately.
	player.camera_pitch = clampf(player.camera_pitch, -.35, 1.05)
	player.update_camera()

## Esc/Backspace and the Back soft key: photo → photos → home → put away.
func go_back() -> void:
	if not active:
		return
	if page == "home":
		close()
	elif page == "photo":
		show_page("photos")
	else:
		show_page("home")

func handle_input(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_P:
		if active:
			close()
		else:
			open()
		return true
	if not active:
		return false
	if not can_open():
		suspend()
		return false
	if event is InputEventKey:
		if event.pressed and not event.echo:
			match event.keycode:
				KEY_ESCAPE, KEY_BACKSPACE:
					go_back()
				KEY_1:
					show_page("contacts")
				KEY_2:
					show_page("camera")
				KEY_3:
					show_page("photos")
				KEY_4:
					show_page("cases")
				KEY_5:
					show_page("police")
				KEY_ENTER, KEY_KP_ENTER:
					if page == "camera":
						request_capture()
					elif page == "police":
						request_police()
				KEY_F5:
					_notice(level.save_progress())
				KEY_M, KEY_F6:
					suspend()
					return false
		# Button focus navigation is handled by the phone GUI, never gameplay.
		if page != "camera" and event.keycode in [KEY_TAB, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SPACE]:
			return false
		if page not in ["camera", "police"] and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			return false
		return true
	if page != "camera":
		return false # level returns early while active, allowing GUI events only.
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or bool(level.get("offscreen_validation")):
			player.look(event.screen_relative)
		return true
	if event is InputEventMouseButton:
		if event.pressed:
			match event.button_index:
				MOUSE_BUTTON_LEFT:
					request_capture()
				MOUSE_BUTTON_WHEEL_UP:
					photo_fov = maxf(32.0, photo_fov - 4.0)
				MOUSE_BUTTON_WHEEL_DOWN:
					photo_fov = minf(82.0, photo_fov + 4.0)
			_refresh_title()
		return true
	return true

func request_police() -> bool:
	if not active or not can_open():
		return false
	if police_requested.get_connections().is_empty():
		set_report_status("Police dispatch is unavailable.")
		return false
	var now := Time.get_ticks_msec()
	if now - _last_police_call < 3000:
		_notice("Please wait before calling again.")
		return false
	_last_police_call = now
	set_report_status("Calling neighborhood officers…")
	police_requested.emit(player.global_position)
	return true

## Police progress for the player's own calls and reports. Several owners may
## deliver one step in the same frame (the call reply and the incident relay);
## the same message still on the banner is not announced again. While the phone
## is put away the update reaches the HUD notice line instead of a hidden banner.
func set_report_status(message: String) -> void:
	var on_banner := active and _feedback != null and _feedback.text == message and _feedback_time > 0.0
	_report_status = message
	_report_generation = _police_generation()
	if active:
		if not on_banner:
			_notice(message)
	else:
		_notify_hud(message)
	if active and page == "police" and (not on_banner or _police_refresh_key() != _police_key):
		show_page("police")

func _notify_hud(message: String) -> void:
	if message.is_empty() or level == null or not level.has_method("show_notice"):
		return
	var now := Time.get_ticks_msec()
	if message == _hud_notice and now - _hud_notice_at < NOTICE_REPEAT_MS:
		return
	_hud_notice = message
	_hud_notice_at = now
	notices_shown += 1
	level.call("show_notice", "Police: " + message)

func _police_service() -> Node:
	return level.get("police_assistance") as Node if level != null else null

func _police_generation() -> int:
	var police := _police_service()
	var value = police.get("generation") if police != null else null
	return int(value) if value is int else -1

## The last police notice, unless a loaded checkpoint has since replaced the
## session it came from: then the neutral prompt, never a stale "on the way".
func _current_report_status() -> String:
	var generation := _police_generation()
	if _report_generation >= 0 and generation >= 0 and generation != _report_generation:
		return DEFAULT_REPORT_STATUS
	return _report_status

## Changes when anything the Police page shows changes (dispatch or records).
func _police_refresh_key() -> String:
	var police := _police_service()
	var incidents: Node = level.get("incidents") as Node if level != null else null
	return "%s:%s:%s" % [str(police.get("revision")) if police != null else "-", str(police.get("generation")) if police != null else "-",
		str(incidents.get("revision")) if incidents != null else "-"]

func _process(delta: float) -> void:
	if not can_open():
		suspend()
		return
	_feedback_time = maxf(0.0, _feedback_time - delta)
	if _feedback_time == 0.0 and not _feedback.text.is_empty():
		_notice("")
	_status_refresh -= delta
	if _status_refresh <= 0.0:
		_refresh_status_bar()
		if page == "police" and _police_refresh_key() != _police_key:
			show_page("police")
	if _viewfinder.flash > 0.0:
		_viewfinder.flash = maxf(0.0, _viewfinder.flash - delta * 4.0)
		_viewfinder.queue_redraw()

func _refresh_title() -> void:
	_viewfinder.zoom_text = "CAMERA   %.1f×" % (tan(deg_to_rad(58.0) * .5) / tan(deg_to_rad(photo_fov) * .5))
	_viewfinder.queue_redraw()

func _notice(message: String) -> void:
	if not message.is_empty():
		notices_shown += 1
	_feedback.text = message
	_banner.visible = not message.is_empty()
	_viewfinder.notice = message
	_viewfinder.queue_redraw()
	_feedback_time = 5.0 if not message.is_empty() else 0.0

## Actual world clock, never a device or wall clock.
func game_clock() -> Dictionary:
	var clock: Node = level.get("world_time") if level != null else null
	if clock == null or not clock.has_method("get_status"):
		return {"time": "--:--", "day": "", "total_minutes": 0.0, "day_index": 0, "minute_of_day": 0.0, "label": ""}
	var status: Dictionary = clock.get_status()
	var whole := floori(float(status.get("minute_of_day", 0.0)))
	return {"time": "%02d:%02d" % [whole / 60, whole % 60], "day": "DAY %d" % (int(status.get("day_index", 0)) + 1),
		"total_minutes": float(status.get("total_minutes", 0.0)), "day_index": int(status.get("day_index", 0)),
		"minute_of_day": float(status.get("minute_of_day", 0.0)), "label": str(status.get("label", ""))}

func _refresh_status_bar() -> void:
	_status_refresh = 0.5
	var clock := game_clock()
	_status_time.text = clock.time
	_status_day.text = clock.day

func request_capture() -> bool:
	if not active or page != "camera" or not can_open() or capturing:
		return false
	if DisplayServer.get_name() == "headless":
		last_error = "Photo capture needs a rendering window."
		_notice(last_error)
		return false
	capturing = true
	_capture.call_deferred(_generation)
	return true

func _capture(generation: int) -> void:
	if not active or generation != _generation:
		capturing = false
		return
	player.update_camera()
	var source: Camera3D = player.camera
	var viewport := SubViewport.new()
	viewport.name = "PhotoExposure"
	viewport.world_3d = get_world_3d()
	viewport.transparent_bg = false
	var screen := get_viewport().get_visible_rect().size
	var scale := minf(1.0, 1280.0 / maxf(maxf(screen.x, screen.y), 1.0))
	viewport.size = Vector2i(maxi(1, roundi(screen.x * scale)), maxi(1, roundi(screen.y * scale)))
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.msaa_3d = get_viewport().msaa_3d
	add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.global_transform = source.global_transform
	camera.fov = source.fov
	camera.near = source.near
	camera.far = source.far
	camera.keep_aspect = source.keep_aspect
	camera.environment = source.environment
	camera.attributes = source.attributes
	camera.cull_mask = source.cull_mask & ~VIEWMODEL_LAYER
	camera.current = true
	var metadata := capture_metadata(viewport.size)
	# Subjects are resolved now, from the same pose, before the GPU readback.
	var context := build_photo_context()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if generation != _generation or not active or not can_open():
		viewport.queue_free()
		capturing = false
		return
	var photo := viewport.get_texture().get_image()
	viewport.queue_free()
	commit_photo(photo, metadata, context)
	capturing = false

## Stores one exposure and, only when it was actually saved, announces it.
func commit_photo(photo: Image, metadata: Dictionary, context: Dictionary) -> Dictionary:
	var details := metadata.duplicate(true)
	details["context"] = PhotoContext.json_safe(context)
	var result := store_photo(photo, details)
	if bool(result.ok):
		photos_taken += 1
		last_photo = result
		last_error = ""
		_viewfinder.flash = 1.0
		_notice("Saved to Photos · %d / %d" % [gallery.entries.size(), Gallery.LIMIT])
		photo_saved.emit(result)
		var announced := context.duplicate(true)
		announced["photo_id"] = str(result.id)
		announced["image_path"] = str(result.image_path)
		captures_emitted += 1
		photo_captured.emit(announced)
	else:
		last_error = str(result.reason)
		_notice(last_error)
	return result

func capture_metadata(size: Vector2i) -> Dictionary:
	var camera: Camera3D = player.camera
	var eye := camera.global_position
	var forward := -camera.global_basis.z
	var player_at := player.global_position
	var clock := game_clock()
	return {"version": 1, "chapter": "pen_lucy", "captured_utc": Time.get_datetime_string_from_system(true),
		"unix_time": Time.get_unix_time_from_system(), "width": size.x, "height": size.y,
		"camera_position": [eye.x, eye.y, eye.z], "camera_forward": [forward.x, forward.y, forward.z],
		"camera_fov": camera.fov, "player_position": [player_at.x, player_at.y, player_at.z],
		"street": _street(player_at), "world_total_minutes": clock.total_minutes,
		"game_time": ("%s · %s" % [clock.day, clock.time]) if not str(clock.day).is_empty() else "",
		"clean_capture": true, "phone_and_hud_excluded": true}

## Live-world description of what the camera sees right now.
func build_photo_context() -> Dictionary:
	var camera: Camera3D = player.camera
	var frame := camera.get_viewport().get_visible_rect().size
	var exclude: Array[RID] = [player.get_rid()]
	var found := PhotoContext.visible_subjects(camera, frame, PhotoContext.candidates(level, _providers), exclude)
	var clock := game_clock()
	return {"version": PhotoContext.VERSION, "source": "phone_camera", "trusted": true, "photo_id": "", "image_path": "",
		"time": {"total_minutes": clock.total_minutes, "day_index": clock.day_index, "minute_of_day": clock.minute_of_day, "label": clock.label},
		"camera": {"position": camera.global_position, "forward": -camera.global_basis.z, "fov": camera.fov,
			"aspect": frame.x / maxf(frame.y, 1.0), "far": camera.far},
		"player_position": player.global_position, "street": _street(player.global_position),
		"subjects": found.subjects, "subjects_considered": found.subjects_considered, "rays_cast": found.rays_cast}

func register_photo_subject_provider(provider: Callable) -> void:
	if provider.is_valid() and not _providers.has(provider):
		_providers.append(provider)

func unregister_photo_subject_provider(provider: Callable) -> void:
	_providers.erase(provider)

## Stored copy from the gallery sidecar. Disk data is never marked trusted.
func get_photo_context(photo_id: String) -> Dictionary:
	for entry in gallery.entries:
		if str(entry.id) != photo_id:
			continue
		var stored: Variant = entry.metadata.get("context")
		if not stored is Dictionary:
			return {}
		var copy: Dictionary = stored.duplicate(true)
		copy["photo_id"] = photo_id
		copy["image_path"] = str(entry.image_path)
		copy["trusted"] = false
		copy["source"] = "phone_gallery"
		return copy
	return {}

func _street(at: Vector3) -> String:
	return str(level.call("_nearest_street", at)) if level != null and level.has_method("_nearest_street") else ""

func store_photo(photo: Image, metadata: Dictionary) -> Dictionary:
	gallery.directory = storage_directory
	return gallery.store(photo, metadata)

func get_status() -> Dictionary:
	return {"active": active, "capturing": capturing, "photos_taken": photos_taken,
		"page": page, "gallery_count": gallery.entries.size(), "gallery_limit": Gallery.LIMIT,
		"fov": photo_fov, "last_photo": last_photo.duplicate(true), "last_error": last_error,
		"report_status": _report_status, "captures_emitted": captures_emitted,
		"police_cards": _police_cards.duplicate(true), "notices": notices_shown,
		"viewmodel_visible": _viewmodel != null and _viewmodel.visible,
		"layout": {"handset": Rect2(_handset.position, _handset.size), "screen": Rect2(_handset.position + _handset.screen.position, _handset.screen.size),
			"viewport": _root.size, "handset_visible": _handset.visible}}

func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 24
	add_child(_overlay)
	_root = Control.new()
	_root.name = "PhoneRoot"
	_root.theme = UI.theme()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_root)
	_viewfinder = UI.Viewfinder.new()
	_root.add_child(_viewfinder)
	_viewfinder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_controls = _label(_root, "", Vector2.ZERO, 17)
	_controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_controls.position = Vector2(24, -38)
	_handset = UI.Handset.new()
	_root.add_child(_handset)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	_handset.screen.add_child(column)
	var status := HBoxContainer.new()
	_status_time = UI.text("--:--", 16, UI.TEXT, "monob")
	_status_day = UI.text("", 16, UI.MUTED, "monob")
	for label in [_status_time, _status_day]:
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.size_flags_horizontal = Control.SIZE_FILL
	status.add_child(_status_time)
	status.add_child(T.expander())
	status.add_child(_status_day)
	column.add_child(_margin(status, 10, 22, 0, 22))
	_feedback = UI.text("", 16, UI.TEXT)
	_banner = _margin(UI.card(_feedback, T.TICKET), 2, 10, 2, 10)
	column.add_child(_banner)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	_header_icon = UI.Glyph.new("contact", Color.WHITE, 34.0)
	header.add_child(_header_icon)
	_header_title = UI.text("", 21, UI.TEXT, "display")
	_header_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_header_title)
	_header = _margin(header, 4, 16, 2, 16)
	column.add_child(_header)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	var padded := _margin(_content, 6, 14, 10, 14)
	padded.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(padded)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 4)
	for definition in [["back", "Back", go_back], ["home", "Home", show_page.bind("home")], ["close", "Put away", close]]:
		var key := UI.NavKey.new(definition[0], definition[1])
		key.pressed.connect(definition[2])
		nav.add_child(key)
	column.add_child(_margin(nav, 2, 10, 8, 10))
	_notice("")
	_overlay.hide()

func _margin(child: Control, top: int, right: int, bottom: int, left: int) -> MarginContainer:
	var margin := MarginContainer.new()
	for edge in [["top", top], ["right", right], ["bottom", bottom], ["left", left]]:
		margin.add_theme_constant_override("margin_" + edge[0], edge[1])
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(child)
	return margin

func _apply_layout() -> void:
	if _handset == null or not is_inside_tree():
		return
	var rect := UI.handset_rect(get_viewport().get_visible_rect().size)
	_handset.position = rect.position
	_handset.size = rect.size
	_handset.arrange()

func show_page(next: String) -> void:
	if next not in PAGES:
		return
	if capturing and next != page:
		_generation += 1 # Cancels the pending exposure without writing a photo.
	page = next
	var camera := page == "camera"
	_handset.visible = not camera
	_viewfinder.visible = camera
	_set_pointer_mode(Input.MOUSE_MODE_CAPTURED if camera else Input.MOUSE_MODE_VISIBLE)
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_scroll.scroll_vertical = 0
	_refresh_title()
	if camera:
		_release_focus()
		_controls.text = "LMB / ENTER Photo   WHEEL Zoom   3 Photos   ESC Back   P Put away"
		return
	_controls.text = "1-5 Apps   Arrows / Tab Move   ENTER Select   ESC Back   P Put away"
	_header.visible = page != "home"
	if page != "home":
		_header_title.text = str(TITLES.get(page, "")).to_upper()
		_header_icon.kind = str(GLYPHS[page][0])
		_header_icon.color = GLYPHS[page][1]
		_header_icon.queue_redraw()
	match page:
		"home":
			_show_home()
		"contacts":
			_show_contacts()
		"photos":
			_show_gallery()
		"photo":
			_show_photo()
		"cases":
			_show_cases()
		"police":
			_show_police()
	_focus_first.call_deferred(_generation)

func _focus_first(generation: int) -> void:
	if not active or generation != _generation or page == "camera" or not _handset.is_visible_in_tree():
		return
	for child in _content.find_children("*", "BaseButton", true, false):
		if child is BaseButton and child.is_visible_in_tree() and child.focus_mode != Control.FOCUS_NONE:
			child.grab_focus()
			return

func _release_focus() -> void:
	if _root == null or not _root.is_inside_tree():
		return
	var focused := _root.get_viewport().gui_get_focus_owner()
	if focused != null and _root.is_ancestor_of(focused):
		focused.release_focus()

func _text(value: String, font_size := 19, color := UI.TEXT, kind := "body600") -> Label:
	var label := UI.text(value, font_size, color, kind)
	_content.add_child(label)
	return label

func _button(value: String, action: Callable, parent: Node = null) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size = Vector2(0, 48)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(action)
	(parent if parent != null else _content).add_child(button)
	return button

func _card(lines: Array, accent := Color.TRANSPARENT) -> PanelContainer:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 3)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for line in lines:
		stack.add_child(UI.text(str(line[0]), int(line[1]), line[2] if line.size() > 2 else UI.TEXT, str(line[3]) if line.size() > 3 else "body600"))
	var panel := UI.card(stack, accent)
	_content.add_child(panel)
	return panel

func _show_home() -> void:
	var clock := game_clock()
	var big := _text(clock.time, 46, UI.TEXT, "display")
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var where := _street(player.global_position)
	var parts := [str(clock.day), where].filter(func(part): return not str(part).is_empty())
	var under := _text(" · ".join(PackedStringArray(parts)), 16, UI.MUTED, "monob")
	under.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var missions: Node = level.get("missions")
	if missions != null and missions.has_method("get_status"):
		var status: Dictionary = missions.get_status()
		if not str(status.get("active_id", "")).is_empty():
			_card([["CURRENT CASE", 14, T.TICKET, "monob"], [str(status.get("title", "Case")), 19], [str(status.get("objective", "")), 16, UI.MUTED]], T.TICKET)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 8)
	_content.add_child(grid)
	for app in UI.APPS:
		var tile := UI.AppTile.new(str(app.page), str(app.title), app.color, str(app.key))
		if app.page == "photos" and not gallery.entries.is_empty():
			tile.badge = str(gallery.entries.size())
		tile.pressed.connect(show_page.bind(str(app.page)))
		grid.add_child(tile)
	if level.has_method("toggle_map"):
		var map_tile := UI.AppTile.new("map", "Map", Color("81d6b1"), "M")
		map_tile.pressed.connect(_open_map)
		grid.add_child(map_tile)

func _open_map() -> void:
	# The level owns the map modal; it suspends the phone itself.
	suspend()
	level.call("toggle_map")

func _show_contacts() -> void:
	_text("Visit neighbors in person to talk.", 16, UI.MUTED)
	# Read the authored directory, including residents currently outside simulation range.
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/pen_lucy_residents.json"))
	if not data is Dictionary:
		_text("The neighborhood directory is unavailable.")
		return
	for definition in data.get("residents", []):
		var name_text := str(definition.get("name", "Neighbor"))
		var initials := ""
		for word in name_text.split(" ", false).slice(0, 2):
			initials += word.left(1).to_upper()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(UI.Glyph.new("contact", Color("70e0da"), 42.0, initials))
		var lines := VBoxContainer.new()
		lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lines.add_theme_constant_override("separation", 1)
		lines.add_child(UI.text(name_text, 19))
		lines.add_child(UI.text(str(definition.get("street", "")), 15, T.TICKET, "monob"))
		var about := str(definition.get("about", ""))
		if not about.is_empty():
			lines.add_child(UI.text(about, 15, UI.MUTED))
		row.add_child(lines)
		var panel := UI.card(row)
		panel.set_meta("contact_id", str(definition.get("id", "")))
		_content.add_child(panel)

func _show_cases() -> void:
	var missions: Node = level.get("missions")
	if missions == null or not missions.has_method("get_status"):
		_text("No case information is available.")
		return
	if missions.has_method("get_phone_cards"):
		var cards: Variant = missions.call("get_phone_cards")
		if cards is Array:
			for entry in cards:
				if entry is Dictionary:
					var current := bool(entry.get("active", false))
					_card([[str(entry.get("title", "Case")), 19], [str(entry.get("state", "")).capitalize(), 14, T.TICKET if current else UI.MUTED, "monob"],
						[str(entry.get("detail", "")), 16, UI.MUTED]], T.TICKET if current else Color.TRANSPARENT)
			if not cards.is_empty():
				return
	var status: Dictionary = missions.get_status()
	if not str(status.get("active_id", "")).is_empty():
		_card([["CURRENT CASE", 14, T.TICKET, "monob"], [str(status.get("title", "Case")), 20], [str(status.get("objective", "")), 16, UI.MUTED]], T.TICKET)
	for entry in status.get("cases", []):
		_card([[str(entry.title), 19], [str(entry.state).capitalize(), 14, UI.MUTED, "monob"], [str(entry.reason), 16, UI.MUTED]])
	for entry in status.get("story", []):
		if entry is Dictionary:
			_card([[str(entry.get("title", "Story")), 19], [str(entry.get("state", "")).capitalize(), 14, UI.MUTED, "monob"], [str(entry.get("reason", "")), 16, UI.MUTED]])
	if _content.get_child_count() == 0:
		_text("No cases yet. Neighbors with a problem will ask you in person.", 17, UI.MUTED)

## Police page: the latest dispatch notice, a report button that names exactly
## what it files (incidents.phone_report_preview), then bounded status cards
## built from live dispatch state and the durable report records (so they are
## rebuilt honestly after a reload). Pull-only: never changes a response.
func _show_police() -> void:
	var police := _police_service()
	var incidents: Node = level.get("incidents") as Node if level != null else null
	var view: Dictionary = {}
	if police != null and police.has_method("dispatch_view"):
		view = police.dispatch_view()
	var records: Array = []
	if incidents != null and incidents.has_method("reports_for"):
		records = incidents.reports_for("player", PoliceStatus.MAX_CARDS)
	var preview: Dictionary = {}
	if incidents != null and incidents.has_method("phone_report_preview"):
		preview = incidents.phone_report_preview(player.global_position)
	_police_cards = PoliceStatus.cards(view, records)
	_police_key = _police_refresh_key()
	_card([["DISPATCH", 14, T.TICKET, "monob"], [_current_report_status(), 19]], Color("7cbcff"))
	var action := PoliceStatus.report_action(preview)
	var dial := _button(str(action.button), request_police)
	dial.set_meta("police_report_kind", str(preview.get("kind", "area_check")))
	dial.custom_minimum_size = Vector2(0, 56)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		dial.add_theme_stylebox_override(state, UI.flat(T.SIREN.lightened(0.08 if state == "hover" else 0.0), 14, 0, Color.TRANSPARENT, 10))
	_text(str(action.hint), 16, UI.MUTED)
	_text(PoliceStatus.DEFAULT_ACTION_HINT, 15, UI.MUTED)
	for i in _police_cards.size():
		_police_card(_police_cards[i], i == 0)

## One status card: what and where, the dispatch stage, then (for the newest)
## responders, the incident as officers know it, a short timeline and the next
## useful step. Times are the game clock; nothing estimates an arrival.
func _police_card(card: Dictionary, expanded: bool) -> void:
	var accent: Color = card.get("accent", Color("7cbcff"))
	var header := str(card.get("title", "")).to_upper()
	if not str(card.get("time", "")).is_empty():
		header += "  ·  " + str(card.time)
	var lines: Array = [[header, 14, accent, "monob"], [str(card.get("label", "")), 19]]
	if not str(card.get("where", "")).is_empty():
		lines.append([str(card.where), 15, T.TICKET, "monob"])
	if expanded:
		if not str(card.get("responders", "")).is_empty():
			lines.append(["Dispatch: " + str(card.responders), 15, UI.MUTED])
		if not str(card.get("incident", "")).is_empty():
			lines.append(["Incident: " + str(card.incident), 15, UI.MUTED])
		if not str(card.get("text", "")).is_empty() and str(card.text) != str(card.get("label", "")):
			lines.append([str(card.text), 16])
		for entry in card.get("timeline", []):
			lines.append(["%s  %s" % [str(entry.get("time", "")), str(entry.get("label", ""))], 14, UI.MUTED, "monob"])
		lines.append(["Next: " + str(card.get("next", "")), 16, T.TICKET])
	var panel := _card(lines, accent)
	panel.set_meta("police_card", str(card.get("key", "")))
	panel.set_meta("police_stage", str(card.get("stage", "")))

func _show_gallery() -> void:
	gallery.directory = storage_directory
	gallery.reload()
	_prune_thumbnails()
	_text("%d / %d stored on this phone" % [gallery.entries.size(), Gallery.LIMIT], 16, UI.MUTED, "monob")
	if gallery.entries.is_empty():
		_text("Your photos will appear here. Open Camera to take one.", 17, UI.MUTED)
		_button("Open Camera", show_page.bind("camera"))
		return
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_content.add_child(grid)
	for entry in gallery.entries:
		var button := _button(_photo_caption(entry.metadata), _open_photo.bind(str(entry.id)), grid)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 128)
		button.add_theme_font_size_override("font_size", 15)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", THUMB_EDGE)
		var texture := _thumbnail(entry)
		if texture != null:
			button.icon = texture
		else:
			button.text = "Photo unavailable"

func _photo_caption(metadata: Dictionary) -> String:
	var label := str(metadata.get("game_time", ""))
	return label if not label.is_empty() else str(metadata.get("street", "Photo"))

func _thumbnail(entry: Dictionary) -> Texture2D:
	var id := str(entry.id)
	if _thumbs.has(id):
		return _thumbs[id]
	var image: Image = gallery.load_image(id)
	if image == null or image.is_empty():
		return null
	var ratio := float(THUMB_EDGE) / maxf(image.get_width(), image.get_height())
	if ratio < 1.0:
		image.resize(maxi(1, roundi(image.get_width() * ratio)), maxi(1, roundi(image.get_height() * ratio)))
	var texture := ImageTexture.create_from_image(image)
	_thumbs[id] = texture
	return texture

func _prune_thumbnails() -> void:
	var present: Dictionary = {}
	for entry in gallery.entries:
		present[str(entry.id)] = true
	for id in _thumbs.keys():
		if not present.has(id):
			_thumbs.erase(id)

func _open_photo(id: String) -> void:
	_selected_photo = id
	show_page("photo")

func _show_photo() -> void:
	var image: Image = gallery.load_image(_selected_photo)
	if image == null or image.is_empty():
		_text("This photo is unavailable.")
	else:
		var viewer := TextureRect.new()
		viewer.texture = ImageTexture.create_from_image(image)
		viewer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		viewer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		viewer.custom_minimum_size = Vector2(0, 200)
		viewer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_content.add_child(viewer)
	for entry in gallery.entries:
		if str(entry.id) != _selected_photo:
			continue
		var metadata: Dictionary = entry.metadata
		var lines: Array = [[_photo_caption(metadata), 18], [str(metadata.get("street", "")), 15, T.TICKET, "monob"]]
		var context: Variant = metadata.get("context")
		if context is Dictionary:
			var names := PackedStringArray()
			for subject in context.get("subjects", []):
				if subject is Dictionary and names.size() < 6:
					names.append(str(subject.get("label", "")))
			lines.append(["In frame: " + ", ".join(names) if not names.is_empty() else "No identified people or places in frame.", 15, UI.MUTED])
		_card(lines)
	_button("Delete this photo", _delete_selected_photo)

func _delete_selected_photo() -> void:
	if not gallery.remove(_selected_photo):
		_notice("Could not delete this photo.")
	_thumbs.erase(_selected_photo)
	show_page("photos")

func _label(parent: Control, text: String, at: Vector2, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", T.body(700))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("eff2e8"))
	label.add_theme_color_override("font_outline_color", Color("111b24"))
	label.add_theme_constant_override("outline_size", 5)
	parent.add_child(label)
	return label

func _build_viewmodel() -> void:
	_viewmodel = Node3D.new()
	_viewmodel.name = "HeldPhoneAndHand"
	player.camera.add_child(_viewmodel)
	_viewmodel.position = Vector3(.27, -.21, -.55)
	_viewmodel.rotation = Vector3(-.10, -.12, -.07)
	var materials: Dictionary = {}
	for key in {"case": "1b2126", "screen": "1f3a44", "trim": "46525a", "skin": "80503a", "sleeve": "41604a"}:
		var material := StandardMaterial3D.new()
		material.albedo_color = Color({"case": "1b2126", "screen": "1f3a44", "trim": "46525a", "skin": "80503a", "sleeve": "41604a"}[key])
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = true
		materials[key] = material
	for part in [[Vector3(.098,.198,.012),Vector3.ZERO,"case"],
		[Vector3(.088,.176,.003),Vector3(0,-.002,.007),"screen"],
		[Vector3(.022,.003,.002),Vector3(0,.092,.008),"trim"],
		[Vector3(.003,.030,.006),Vector3(.050,.040,0),"trim"],
		[Vector3(.062,.095,.032),Vector3(.056,-.068,-.005),"skin"],
		[Vector3(.021,.068,.020),Vector3(.046,-.041,.024),"skin"],
		[Vector3(.070,.16,.052),Vector3(.065,-.185,-.008),"sleeve"]]:
		var mesh := BoxMesh.new()
		mesh.size = part[0]
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.position = part[1]
		instance.material_override = materials[part[2]]
		instance.layers = VIEWMODEL_LAYER
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_viewmodel.add_child(instance)
	_viewmodel.hide()

func _exit_tree() -> void:
	_generation += 1
	if active and is_instance_valid(_hud):
		_hud.visible = _hud_was_visible
	if is_instance_valid(player) and player.phone == self:
		player.phone = null
	if is_instance_valid(_viewmodel):
		_viewmodel.queue_free()
