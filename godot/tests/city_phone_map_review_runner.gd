extends Node
## UI review captures: every phone page and the full map at 720p, 900p, a 4:3
## window and an ultrawide window. Graphical offscreen fixture run by root;
## it never captures, warps or releases the desktop pointer.
const Explorer = preload("res://scripts/city/city_player.gd")
const Phone = preload("res://scripts/city/city_player_phone.gd")
const Combat = preload("res://scripts/city/city_combat.gd")
const WorldTime = preload("res://scripts/city/city_world_time.gd")
const MapOverlay = preload("res://scripts/city/city_map_overlay.gd")
const PAGES := ["home", "contacts", "photos", "photo", "cases", "police", "camera"]
const WINDOWS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1024, 768), Vector2i(1920, 820)]
var failures := 0
var checks: Array[Dictionary] = []
var captures: Array[Dictionary] = []
var output := ""

class Missions extends Node:
	# Display-only fixture using an existing case title; it adds no story.
	func get_status() -> Dictionary:
		return {"active_id": "lost_satchel", "title": "Lost satchel", "objective": "Ask along Old York Road who saw the satchel.",
			"cases": [{"title": "Lost satchel", "state": "active", "reason": "A neighbor asked for help."},
				{"title": "The opened parcel", "state": "available", "reason": "Talk to the neighbor on the porch."}], "story": []}

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
	var _ui: CanvasLayer
	func save_progress() -> String:
		return "Progress saved."
	func _nearest_street(_at: Vector3) -> String:
		return "Old York Road"

class MapPlayer extends Node3D:
	var camera_yaw := PI
	var yaw := 0.0

class MapLevel extends Node3D:
	var level_data: Dictionary
	var player: Node3D
	var civic_district: RefCounted
	var mission_navigation: RefCounted
	var landmarks: Array = []
	var visited: Dictionary = {}
	var npcs: Node
	var traffic: Node
	func vector(value) -> Vector3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	func resume_exploring() -> void:
		pass

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
	print("[phone_map_review] %s %s" % ["PASS" if ok else "FAIL", label])
	failures += int(not ok)

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not "--offscreen-validation" in OS.get_cmdline_user_args():
		push_error("UI review captures require a graphical renderer and --offscreen-validation.")
		get_tree().quit(2)
		return
	output = ProjectSettings.globalize_path("res://../.work/pacifist-foundation/phone-map-review")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-out="):
			output = arg.trim_prefix("--review-out=")
	DirAccess.make_dir_recursive_absolute(output)
	var pointer := Input.mouse_mode
	var level := _world()
	var phone := Phone.new()
	level.add_child(phone)
	phone.setup(level, level.player)
	phone.storage_directory = "user://phone_gallery_test_review_%d" % Time.get_ticks_usec()
	var first_id := _sample_photos(phone)
	await frames(3)
	phone.open()
	for window_size in WINDOWS:
		get_window().size = window_size
		await frames(4)
		for page in PAGES:
			if page == "photo":
				phone._open_photo(first_id)
			else:
				phone.show_page(page)
			await frames(4)
			var layout: Dictionary = phone.get_status().layout
			var visible_rect := Rect2(Vector2.ZERO, layout.viewport)
			if page != "camera":
				check(visible_rect.grow(0.5).encloses(layout.handset), "%s handset fits %dx%d" % [page, window_size.x, window_size.y])
			_capture("phone-%dx%d-%s" % [window_size.x, window_size.y, page], {"page": page, "handset": str(layout.handset), "viewport": str(layout.viewport)})
	phone.suspend()
	var map_level := _map_world()
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var overlay := MapOverlay.new()
	layer.add_child(overlay)
	overlay.setup(map_level, func(): pass)
	overlay.show()
	for window_size in WINDOWS:
		get_window().size = window_size
		overlay.map.fit_neighborhood()
		overlay.map.hovered_poi = ""
		await frames(4)
		_capture("map-%dx%d" % [window_size.x, window_size.y], {"page": "map"})
		var entries: Array[Dictionary] = overlay.map.poi_entries()
		if not entries.is_empty():
			overlay.map.select_poi(str(entries[0].id))
			await frames(3)
			_capture("map-%dx%d-selected" % [window_size.x, window_size.y], {"page": "map", "selected": str(entries[0].short)})
			overlay.map.select_poi("")
		var key_bottom: float = overlay.key.get_global_rect().end.y
		check(key_bottom <= overlay.get_global_rect().end.y + 0.5 and overlay.map.size.y >= 240.0,
			"map keeps a usable canvas and its key on screen at %dx%d" % [window_size.x, window_size.y])
	for entry in phone.gallery.entries.duplicate():
		phone.gallery.remove(str(entry.id))
	DirAccess.remove_absolute(phone.storage_directory)
	check(Input.mouse_mode == pointer, "review never changes the desktop pointer mode")
	var file := FileAccess.open(output.path_join("review.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures": failures, "checks": checks, "captures": captures}, "\t"))
	file.close()
	print("[phone_map_review] ", checks.size() - failures, " passed, ", failures, " failed; ", output)
	get_tree().quit(0 if failures == 0 else 1)

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
	floor.add_child(_box(Vector3(60, 1, 60), Vector3(0, -.5, 0), Color("6f7466")))
	level.add_child(floor)
	# Simple street furniture so the camera viewfinder frames a real world.
	for definition in [[Vector3(8, 6, 6), Vector3(-6, 3, 14), Color("b07a5a")], [Vector3(6, 9, 6), Vector3(5, 4.5, 18), Color("8c8f9c")],
		[Vector3(.3, 3, .3), Vector3(1.5, 1.5, 7), Color("2b3036")], [Vector3(1.2, 1.2, 1.2), Vector3(-1.2, .6, 6), Color("d0b25a")]]:
		level.add_child(_box(definition[0], definition[1], definition[2]))
	level._ui = CanvasLayer.new()
	level.add_child(level._ui)
	level.world_time = WorldTime.new()
	level.add_child(level.world_time)
	level.world_time.set_time(17 * 60 + 42, 2)
	level.missions = Missions.new()
	level.add_child(level.missions)
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

func _box(size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	instance.material_override = material
	return instance

func _sample_photos(phone: Node3D) -> String:
	var first := ""
	for i in 3:
		var image := Image.create(320, 180, false, Image.FORMAT_RGBA8)
		for y in 180:
			var t := float(y) / 179.0
			image.fill_rect(Rect2i(0, y, 320, 1), Color(0.35 + 0.2 * i, 0.55, 0.75).lerp(Color("4d5a4a"), t))
		image.fill_rect(Rect2i(40 + 60 * i, 70, 70, 110), Color("b07a5a"))
		var context := {"version": 2, "source": "phone_camera", "trusted": true,
			"time": {"label": "DAY 3  ·  17:%02d" % (30 + i)},
			"subjects": [{"id": "fixture_%d" % i, "kind": "place", "label": "Corner Store", "distance": 9.0 + i}]}
		var metadata: Dictionary = phone.capture_metadata(Vector2i(320, 180))
		var result: Dictionary = phone.commit_photo(image, metadata, context)
		check(result.ok, "sample gallery photo %d stored" % i)
		if first.is_empty() and result.ok:
			first = str(result.id)
	return first

func _map_world() -> MapLevel:
	var level := MapLevel.new()
	level.level_data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/pen_lucy_level.json"))
	level.player = MapPlayer.new()
	level.add_child(level.player)
	add_child(level)
	return level
