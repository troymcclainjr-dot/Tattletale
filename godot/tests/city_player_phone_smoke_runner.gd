extends Node
const Explorer = preload("res://scripts/city/city_player.gd")
const Phone = preload("res://scripts/city/city_player_phone.gd")
const Combat = preload("res://scripts/city/city_combat.gd")
const PhoneUI = preload("res://scripts/city/city_phone_ui.gd")
const PhotoContext = preload("res://scripts/city/city_photo_context.gd")
const CaseEvidence = preload("res://scripts/city/city_case_evidence.gd")
const WorldTime = preload("res://scripts/city/city_world_time.gd")
class LevelFixture:
	extends Node3D
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
	var _ui: CanvasLayer
	var saves := 0
	func save_progress() -> String:
		saves += 1
		return "Progress saved."
	func _nearest_street(_at: Vector3) -> String:
		return "Phone fixture street"
class ActorDirectory:
	extends Node
	var actors: Dictionary = {}
var failures := 0

func _ready() -> void:
	_run.call_deferred()
func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("[player_phone] %s %s" % ["PASS" if ok else "FAIL", label])
func key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event
func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _run() -> void:
	G.built = false
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	var level := LevelFixture.new()
	add_child(level)
	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(30,1,30)
	var collision := CollisionShape3D.new()
	collision.shape = floor_shape
	collision.position.y = -.5
	floor.add_child(collision)
	level.add_child(floor)
	level._ui = CanvasLayer.new()
	level.add_child(level._ui)
	level.player = Explorer.new()
	level.add_child(level.player)
	level.player.enabled = true
	level.player.position = Vector3(0,.05,0)
	level.combat = Combat.new()
	level.add_child(level.combat)
	level.combat.setup(level)
	var phone := Phone.new()
	level.add_child(phone)
	phone.setup(level,level.player)
	phone.storage_directory = "user://phone_gallery_test_%d" % Time.get_ticks_usec()
	level.world_time = WorldTime.new()
	level.add_child(level.world_time)
	level.world_time.set_time(9 * 60 + 5, 1)
	await frames(3)
	var original_mode: bool = level.player.first_person
	var original_pointer: int = Input.mouse_mode
	check(phone.handle_input(key(KEY_P)) and phone.active, "P raises phone from gameplay")
	check(phone.page == "home" and Input.mouse_mode == original_pointer, "offscreen phone opens without changing desktop pointer mode")
	check(not phone.request_capture(), "home page cannot accidentally capture the world")
	await frames(2)
	await _layout_checks(phone)
	await _pointer_and_keyboard_checks(phone)
	phone.show_page("home")
	phone.handle_input(key(KEY_1))
	check(phone.page == "contacts" and _contact_rows(phone) == 20, "Contacts lists the twenty authored residents as rows")
	phone.handle_input(key(KEY_4))
	check(phone.page == "cases", "Cases opens gracefully when no mission provider is attached")
	phone.handle_input(key(KEY_5))
	check(not phone.request_police(), "missing dispatch connection does not promise police response")
	var calls: Array[Vector3] = []
	phone.police_requested.connect(func(position: Vector3): calls.append(position))
	check(phone.request_police() and calls.size() == 1 and calls[0] == level.player.global_position, "police signal carries the real player location")
	check(not phone.request_police() and calls.size() == 1, "police repeat calls are debounced")
	phone.set_report_status("Officer dispatched to nearby violence.")
	check(phone.get_status().report_status == "Officer dispatched to nearby violence.", "dispatch result is visible in the phone")
	phone.handle_input(key(KEY_2))
	check(phone.page == "camera" and Input.mouse_mode == original_pointer, "offscreen Camera preserves desktop pointer mode")
	check(phone.get_status().viewmodel_visible and not level._ui.visible, "held phone visible and ordinary HUD cleared for composition")
	check(not phone.get_status().layout.handset_visible and phone._viewfinder.visible, "Camera swaps the handset for a full-screen world viewfinder")
	check(not level.combat.request_attack() and level.combat.shots_fired==0 and level.combat.punches_thrown==0, "direct attacks rejected while phone owns input")
	var before_clock: float = level.combat._clock
	level.combat.tick(.05)
	check(level.combat._clock>before_clock and level.combat._hurt_player(1.0), "phone does not freeze combat simulation or grant damage immunity")
	check(phone.handle_input(key(KEY_SPACE)) and not level.player.request_jump(), "phone consumes jump without launching player")
	var at: Vector3 = level.player.global_position
	Input.action_press("move_forward")
	await frames(3)
	Input.action_release("move_forward")
	check(Vector2(level.player.global_position.x-at.x,level.player.global_position.z-at.z).length()<.005, "raw held movement keys cannot leak through modal input")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	phone.handle_input(wheel)
	level.player.update_camera()
	check(phone.photo_fov==54.0 and level.player.camera.fov==54.0, "wheel zoom changes actual photo camera")
	phone.handle_input(key(KEY_F5))
	check(level.saves==1 and phone.active, "save progress routed without closing or resuming another UI")
	phone.handle_input(key(KEY_ESCAPE))
	check(phone.active and phone.page == "home", "Escape from an app returns home")
	phone.handle_input(key(KEY_ESCAPE))
	check(not phone.active and level._ui.visible and level.player.first_person==original_mode, "Escape from home restores HUD and original camera mode")
	check(Input.mouse_mode == original_pointer, "offscreen phone close preserves desktop pointer mode")
	phone.open()
	phone.show_page("camera")
	level.paused = true
	level.player.enabled = false
	phone.suspend()
	check(level.paused and not level.player.enabled and not phone.active, "suspending for menu never resumes gameplay")
	check(not phone.open(), "phone cannot reopen behind pause UI")
	level.paused = false
	level.player.enabled = true
	get_tree().paused = true
	check(not phone.open(), "tree pause also prevents phone capture mode")
	get_tree().paused = false
	phone.open()
	var photo := Image.create(32,20,false,Image.FORMAT_RGBA8)
	photo.fill(Color(.1,.5,.8,1))
	var metadata := phone.capture_metadata(Vector2i(32,20))
	var first := phone.store_photo(photo,metadata)
	var second := phone.store_photo(photo,metadata)
	check(first.ok and second.ok and first.image_path!=second.image_path and first.image_path.begins_with("user://phone_gallery_test_"), "internal gallery persists unique photos without external paths")
	if first.ok:
		var restored := Image.load_from_file(first.image_path)
		var details = JSON.parse_string(FileAccess.get_file_as_string(first.metadata_path))
		check(restored!=null and restored.get_size()==Vector2i(32,20) and details.street=="Phone fixture street"
			and details.camera_position.size()==3 and details.phone_and_hud_excluded, "stored PNG and JSON preserve image dimensions and composition metadata")
		var directory := phone.storage_directory
		phone.storage_directory = first.image_path
		var failed := phone.store_photo(photo,metadata)
		check(not failed.ok and FileAccess.file_exists(first.image_path) and FileAccess.file_exists(first.metadata_path), "failed save preserves existing photo pair")
		phone.storage_directory = directory
		phone.show_page("photos")
		check(phone.gallery.entries.size() == 2, "Photos reloads both stored images")
		phone._open_photo(str(first.id))
		var has_viewer := false
		for child in phone._content.get_children():
			if child is TextureRect and child.texture != null:
				has_viewer = true
		check(has_viewer, "selected gallery photo creates a real image viewer")
		phone._delete_selected_photo()
		check(phone.page == "photos" and phone.gallery.entries.size() == 1 and not FileAccess.file_exists(first.image_path), "gallery deletion removes only the selected photo")
		for i in range(Phone.Gallery.LIMIT - 1):
			check(phone.store_photo(photo, metadata).ok, "gallery bounded fill %d" % i)
		check(not phone.store_photo(photo, metadata).ok and phone.gallery.entries.size() == Phone.Gallery.LIMIT, "full gallery refuses additional photos without evicting saved ones")
		for entry in phone.gallery.entries.duplicate():
			phone.gallery.remove(str(entry.id))
		DirAccess.remove_absolute(directory)
	await _context_checks(level, phone, photo)
	phone.show_page("camera")
	if "--phone-render" in OS.get_cmdline_user_args():
		await _render_check(level,phone)
	else:
		check(DisplayServer.get_name()!="headless" or not phone.request_capture(), "headless capture declines cleanly without invalid viewport read")
	for entry in phone.gallery.entries.duplicate():
		phone.gallery.remove(str(entry.id))
	DirAccess.remove_absolute(phone.storage_directory)
	phone.suspend()
	check(Input.mouse_mode == original_pointer, "photo/gallery validation never changes desktop pointer mode")
	level.queue_free()
	await frames(1)
	print("[player_phone] failures=",failures)
	get_tree().quit(0 if failures==0 else 1)

func _render_check(level: Node3D,phone: Node3D) -> void:
	if DisplayServer.get_name()=="headless":
		check(false,"GPU capture fixture requires rendered offscreen window")
		return
	level.player.camera_pitch = 0.0
	level.player.camera_yaw = 0.0
	level.player.update_camera()
	# A blue world wall, with a red HUD and yellow viewmodel deliberately over
	# the main view. The saved camera must see only the blue world geometry.
	var wall := MeshInstance3D.new()
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(40,30,1)
	wall.mesh = wall_mesh
	wall.position = Vector3(0,1.64,7)
	var blue := StandardMaterial3D.new()
	blue.albedo_color = Color(.05,.1,.85)
	blue.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wall.material_override = blue
	level.add_child(wall)
	var overlay := ColorRect.new()
	overlay.color = Color.RED
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	phone._overlay.add_child(overlay)
	var blocker := MeshInstance3D.new()
	var blocker_mesh := BoxMesh.new()
	blocker_mesh.size = Vector3(5,5,.02)
	blocker.mesh = blocker_mesh
	blocker.position = Vector3(0,0,-.3)
	blocker.layers = Phone.VIEWMODEL_LAYER
	var yellow := StandardMaterial3D.new()
	yellow.albedo_color = Color.YELLOW
	yellow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blocker.material_override = yellow
	level.player.camera.add_child(blocker)
	await frames(2)
	var announced: Array[Dictionary] = []
	phone.photo_captured.connect(func(context: Dictionary): announced.append(context))
	var photos_before: int = phone.photos_taken
	check(phone.request_capture(), "rendered phone requests one exposure")
	check(not phone.request_capture(), "double click cannot queue duplicate in-flight exposures")
	for i in 120:
		if not phone.capturing:
			break
		await frames(1)
	check(phone.photos_taken == photos_before + 1 and phone.last_error.is_empty(), "rendered photo completes and reports saved path")
	check(announced.size() == 1 and bool(announced[0].trusted) and str(announced[0].photo_id) == str(phone.last_photo.get("id", "-")),
		"rendered exposure announces exactly one trusted photo context")
	if not phone.last_photo.is_empty():
		var image := Image.load_from_file(phone.last_photo.image_path)
		var center := image.get_pixel(image.get_width()/2,image.get_height()/2)
		check(center.b>center.r*2.0 and center.b>center.g*2.0, "actual saved PNG excludes both red HUD and yellow held-phone layer")
	# Abandoning phone mode before deferred exposure must not create a file or
	# return the player to gameplay behind another modal owner.
	check(phone.request_capture(), "second exposure can begin after first completes")
	phone.suspend()
	await frames(2)
	check(phone.photos_taken == photos_before + 1 and not phone.capturing and not phone.active, "closing during capture cancels without stray image or reopening")
	check(announced.size() == 1, "cancelled exposure announces no photo context")

func _contact_rows(phone: Node3D) -> int:
	var rows := 0
	for child in phone._content.get_children():
		if child.has_meta("contact_id"):
			rows += 1
	return rows

func _inside(outer: Rect2, inner: Rect2) -> bool:
	return outer.grow(0.5).encloses(inner)

## Portrait handset geometry: pure placement for several logical viewports,
## then the live tree at the current one.
func _layout_checks(phone: Node3D) -> void:
	# canvas_items/expand keeps one axis at 1600x900; windowed and 4:3/ultrawide
	# windows grow the other. Smaller sizes guard a custom stretch setting.
	for view in [Vector2(1600, 900), Vector2(1600, 1200), Vector2(2400, 900), Vector2(1280, 720), Vector2(800, 600), Vector2(640, 1000)]:
		var rect: Rect2 = PhoneUI.handset_rect(view)
		var screen: Rect2 = PhoneUI.screen_rect(rect)
		check(_inside(Rect2(Vector2.ZERO, view), rect) and rect.size.y > rect.size.x * 1.7 and rect.size.y >= minf(360.0, view.y * 0.9) - 0.5
			and _inside(rect, screen), "portrait handset fits %dx%d with an inset screen" % [view.x, view.y])
	var layout: Dictionary = phone.get_status().layout
	var visible_rect := Rect2(Vector2.ZERO, layout.viewport)
	check(layout.handset_visible and _inside(visible_rect, layout.handset) and _inside(layout.handset, layout.screen), "live handset and screen fit the current viewport")
	var tiles: Array = phone._content.find_children("App_*", "BaseButton", true, false)
	check(tiles.size() == 5, "home shows the five apps without a map app in a level that has no map")
	var all_inside := true
	for tile in tiles:
		all_inside = all_inside and _inside(layout.screen, tile.get_global_rect()) and tile.size.y >= 44.0 and tile.size.x >= 44.0
	check(all_inside, "every app tile is a full-size target inside the screen")
	var nav: Array = phone._handset.find_children("Nav_*", "BaseButton", true, false)
	var nav_ok := nav.size() == 3
	for key in nav:
		nav_ok = nav_ok and _inside(layout.screen, key.get_global_rect()) and key.size.y >= 44.0
	check(nav_ok, "Back, Home and Put away soft keys sit inside the screen")
	phone._refresh_status_bar()
	check(phone._status_time.text == "09:05" and phone._status_day.text == "DAY 2", "status bar shows the actual world clock")
	check(not phone._banner.visible, "empty notification banner stays hidden")

func _click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		get_viewport().push_input(event, true)
		await get_tree().process_frame

## A real key press/release through the viewport GUI, as the level forwards it
## when the phone declines the event. `action` documents the expected mapping.
func _ui_key(code: Key, action: String) -> void:
	check(InputMap.has_action(action), "%s is mapped for phone GUI navigation" % action)
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await get_tree().process_frame

func _pointer_and_keyboard_checks(phone: Node3D) -> void:
	var photos: Array = phone._content.find_children("App_photos", "BaseButton", true, false)
	if photos.is_empty():
		check(false, "Photos app tile exists")
		return
	await _click(photos[0])
	check(phone.page == "photos", "mouse click on an app tile opens it")
	var back: Array = phone._handset.find_children("Nav_back", "BaseButton", true, false)
	await _click(back[0])
	check(phone.page == "home" and phone.active, "Back soft key returns to home")
	phone.show_page("police")
	await frames(1)
	var home: Array = phone._handset.find_children("Nav_home", "BaseButton", true, false)
	await _click(home[0])
	check(phone.page == "home", "Home soft key returns home from any app")
	await frames(2)
	var focused := get_viewport().gui_get_focus_owner()
	check(focused != null and str(focused.name).begins_with("App_"), "home focuses the first app for keyboard use")
	await _ui_key(KEY_RIGHT, "ui_right")
	var moved := get_viewport().gui_get_focus_owner()
	check(moved != null and moved != focused and str(moved.name).begins_with("App_"), "arrow keys move between app tiles")
	if moved != null:
		var expected := str(moved.name).trim_prefix("App_")
		check(not phone.handle_input(key(KEY_ENTER)), "Enter on an app page is left to the focused control")
		await _ui_key(KEY_ENTER, "ui_accept")
		check(phone.page == expected, "Enter opens the focused app")
	phone.show_page("home")
	await frames(2)
	var close: Array = phone._handset.find_children("Nav_close", "BaseButton", true, false)
	await _click(close[0])
	check(not phone.active, "Put away soft key closes the phone")
	phone.open()
	await frames(2)

## Trusted evidence context: identified world subjects in frame with clear
## line of sight, provider subjects, bounded JSON and exactly-once emission.
func _context_checks(level: Node3D, phone: Node3D, photo: Image) -> void:
	level.player.camera_pitch = 0.0
	level.player.camera_yaw = 0.0
	level.player.update_camera()
	var camera: Camera3D = level.player.camera
	var eye := camera.global_position
	var forward := -camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var side := forward.cross(Vector3.UP).normalized()
	var subjects: Array[Node] = []
	for definition in [["visible_sign", eye + forward * 6.0], ["hidden_sign", eye + forward * 14.0 + side * 0.2], ["behind_sign", eye - forward * 5.0]]:
		var body := StaticBody3D.new()
		body.collision_layer = 2
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(.8, .8, .8)
		shape.shape = box
		body.add_child(shape)
		body.add_to_group(PhotoContext.GROUP)
		body.set_meta("photo_subject_id", definition[0])
		body.set_meta("photo_subject_kind", "object")
		body.set_meta("photo_subject_label", str(definition[0]).capitalize())
		level.add_child(body)
		body.global_position = definition[1]
		subjects.append(body)
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(6, 6, .4)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	level.add_child(wall)
	wall.global_transform = Transform3D(Basis.looking_at(forward), eye + forward * 10.0)
	# A thin screen 0.4 m in front of a subject: inside its framing radius, but
	# it still blocks the view, so strict line of sight must reject it.
	var screen_panel := StaticBody3D.new()
	var screen_shape := CollisionShape3D.new()
	var screen_box := BoxShape3D.new()
	screen_box.size = Vector3(1.2, 2.0, .1)
	screen_shape.shape = screen_box
	screen_panel.add_child(screen_shape)
	level.add_child(screen_panel)
	screen_panel.global_transform = Transform3D(Basis.looking_at(forward), eye + forward * 7.6 + side * 1.5)
	# Named actors come from the level's actor directory; custody hides them.
	var directory := ActorDirectory.new()
	level.add_child(directory)
	level.npcs = directory
	for definition in [["witness", -2.0, false], ["detained", 2.5, true]]:
		var actor := StaticBody3D.new()
		var actor_shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = .3
		capsule.height = 1.7
		actor_shape.shape = capsule
		actor_shape.position.y = .85
		actor.add_child(actor_shape)
		directory.add_child(actor)
		actor.global_position = Vector3(eye.x, eye.y - PhotoContext.ACTOR_HEIGHT, eye.z) + forward * 5.0 + side * float(definition[1])
		actor.set_meta("police_custody", definition[2])
		directory.actors[definition[0]] = actor
		subjects.append(actor)
	await frames(3)
	var provider := func() -> Array:
		return [{"id": "case_target", "kind": "evidence", "label": "Case target", "position": eye + forward * 4.0 - side * 1.0, "tags": ["fixture"]},
			{"id": "screened_target", "kind": "evidence", "label": "Screened", "position": eye + forward * 8.0 + side * 1.5, "radius": 0.6}]
	phone.register_photo_subject_provider(provider)
	phone.register_photo_subject_provider(provider)
	var context: Dictionary = phone.build_photo_context()
	var ids: Array = []
	for subject in context.subjects:
		ids.append(subject.id)
	check("visible_sign" in ids, "framed subject with clear line of sight is identified")
	check("hidden_sign" not in ids, "subject behind a wall is excluded by line of sight")
	check("behind_sign" not in ids, "subject behind the camera is excluded")
	check(ids.count("case_target") == 1, "registered provider subject is evaluated once")
	check("screened_target" not in ids, "an obstacle within the subject's radius still blocks line of sight")
	var witness: Dictionary = context.subjects[ids.find("witness")] if "witness" in ids else {}
	check(not witness.is_empty() and witness.kind == "actor", "named actor in view is identified from the level's actor directory")
	check("detained" not in ids, "actors in police custody are not photo subjects")
	var visible: Dictionary = context.subjects[ids.find("visible_sign")] if "visible_sign" in ids else {}
	check(not visible.is_empty() and visible.line_of_sight and visible.screen.x > 0.3 and visible.screen.x < 0.7 and visible.centrality > 0.5
		and absf(visible.distance - 6.0) < 0.6, "subject carries frame position, centrality and distance")
	check(context.trusted and context.time.day_index == 1 and is_equal_approx(context.time.minute_of_day, 545.0) and context.camera.position.is_equal_approx(camera.global_position),
		"context records live game time and the exact camera pose")
	check(PhotoContext.STATIC_MASK == CaseEvidence.STATIC_MASK, "phone listing and case evidence use the same static occlusion layers")
	var passing := StaticBody3D.new()
	var passing_shape := CollisionShape3D.new()
	var passing_capsule := CapsuleShape3D.new()
	passing_capsule.radius = .35
	passing_capsule.height = 1.7
	passing_shape.shape = passing_capsule
	passing.add_child(passing_shape)
	level.add_child(passing)
	passing.global_position = eye + forward * 3.0
	for layer in [8, 16, 2, 1]:
		passing.collision_layer = layer
		await frames(2)
		var listed := false
		for entry in phone.build_photo_context().subjects:
			listed = listed or (str(entry.id) == "visible_sign" and bool(entry.line_of_sight))
		check(listed == (layer == 8 or layer == 16), "photo occlusion respects real collider layer %d" % layer)
	passing.collision_layer = 0
	passing.queue_free()
	await frames(2)
	var restored_static_subject := false
	for entry in phone.build_photo_context().subjects:
		restored_static_subject = restored_static_subject or str(entry.id) == "visible_sign"
	check(restored_static_subject, "a subject's own layer-2 collider is accepted after a blocker leaves")
	phone.unregister_photo_subject_provider(provider)
	var without: Array = []
	for subject in phone.build_photo_context().subjects:
		without.append(subject.id)
	check("case_target" not in without, "unregistered provider is no longer consulted")
	var crowd := func() -> Array:
		var many: Array = []
		for i in 40:
			many.append({"id": "crowd_%d" % i, "kind": "evidence", "label": "Fixture subject %d with a deliberately long descriptive label" % i,
				"position": eye + forward * (3.0 + i * 0.15) + side * (float(i % 5) - 2.0) * 0.3, "tags": ["a", "b", "c"]})
		return many
	phone.register_photo_subject_provider(crowd)
	var crowded: Dictionary = phone.build_photo_context()
	check(crowded.subjects.size() == PhotoContext.MAX_SUBJECTS and crowded.rays_cast <= PhotoContext.MAX_RAYS and crowded.subjects_considered > PhotoContext.MAX_SUBJECTS,
		"subject and ray counts stay bounded when many subjects are framed")
	var nearest_first := true
	for i in range(1, crowded.subjects.size()):
		nearest_first = nearest_first and crowded.subjects[i - 1].distance <= crowded.subjects[i].distance
	check(nearest_first, "bounded subjects keep the nearest first")
	var announced: Array[Dictionary] = []
	var listener := func(value: Dictionary): announced.append(value)
	phone.photo_captured.connect(listener)
	phone.storage_directory = "user://phone_gallery_test_ctx_%d" % Time.get_ticks_usec()
	var metadata: Dictionary = phone.capture_metadata(Vector2i(32, 20))
	var stored: Dictionary = phone.commit_photo(photo, metadata, crowded)
	check(stored.ok and announced.size() == 1 and announced[0].photo_id == stored.id and announced[0].image_path == stored.image_path
		and announced[0].subjects.size() == crowded.subjects.size(), "stored photo announces one trusted context with its gallery id")
	phone.gallery.reload()
	var restored: Dictionary = phone.get_photo_context(str(stored.get("id", "")))
	check(phone.gallery.entries.size() == 1 and not restored.is_empty() and not restored.trusted and restored.subjects.size() == crowded.subjects.size()
		and restored.subjects[0].position is Array, "bounded sidecar reloads as an untrusted stored copy")
	phone._open_photo(str(stored.get("id", "")))
	var described := false
	for label in phone._content.find_children("*", "Label", true, false):
		described = described or label.text.begins_with("In frame: ")
	check(described, "photo viewer lists identified subjects")
	for i in range(phone.gallery.entries.size(), Phone.Gallery.LIMIT):
		phone.store_photo(photo, metadata)
	var refused: Dictionary = phone.commit_photo(photo, metadata, crowded)
	check(not refused.ok and announced.size() == 1, "refused save announces nothing")
	phone.photo_captured.disconnect(listener)
	phone.unregister_photo_subject_provider(crowd)
	for entry in phone.gallery.entries.duplicate():
		phone.gallery.remove(str(entry.id))
	DirAccess.remove_absolute(phone.storage_directory)
	phone.storage_directory = "user://phone_gallery_test_%d" % Time.get_ticks_usec()
	for node in subjects:
		node.queue_free()
	wall.queue_free()
	screen_panel.queue_free()
	level.npcs = null
	directory.queue_free()
	await frames(1)
