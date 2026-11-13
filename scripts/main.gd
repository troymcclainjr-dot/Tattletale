extends Node3D
## Pivot prototype: the studio from the street to the vocal booth (building.gd),
## the lead, and a second character who wanders the control room and can be
## talked to. You arrive on the street, in front of the door.
##
##   WASD / arrows  walk          E       use whatever is nearest: talk, open a door
##   1 - 9          swap the lead between the character options
##   Tab            next camera (starts on the one that follows him)
##   C              ceiling on / off
##   Z / X          previous / next expression (characters with loose face parts)
##   Space (hold)   move his mouth          F       close-up on / off
##   F8             save a PNG to user://shots
##
## In a conversation: click a line (it turns yellow under the mouse) or press
## its number; E, Space, Enter or a click moves on.
##
## Screenshot mode (used by tools/shot.py):
##   godot --path popup -- --shot=C:/out.png --cam=angle --char=e [--at=x,z] [--no-ceiling]
##         [--face=angry] [--mouth=mouth_ah] [--close] [--talk=seconds]
##         [--walk=x,y,seconds] [--rest=seconds] [--fry-at=x,z] [--wander]
##         [--do=step,step,...] [--check-faces]
##   Steps run in order after the walk: use (press E), wait:seconds, hover:n,
##   pick:n, next (E in a conversation), clickbox (click the talk box), go:x:z (walk straight to that spot on
##   the floor), frywalk:x:y:seconds (walk the other character on screen).

const Building := preload("res://scripts/building.gd")
const FlickerCheck := preload("res://scripts/flicker_check.gd")
const PaperActor := preload("res://scripts/paper_actor.gd")
const Wanderer := preload("res://scripts/wanderer.gd")
const TalkBox := preload("res://scripts/talk_box.gd")
const FONT := preload("res://assets/fonts/Bungee-Regular.ttf")   # Pen Lucy's display font

## The follow camera keeps this far from him, off to the right. It may not go
## past the right wall of the room he is in (each room says how far) or rise to
## the ceiling, or they hide the room.
const FOLLOW_OFFSET := Vector3(2.3, 0.0, 4.6)
const START := Vector3(1.97, 0, 7.35)      # on the pavement, in front of the street door

## name: [camera position, look-at point, vertical field of view]
## "angle" is the whole room from the game's side: off to the right of the open
## front, low enough to stay under the ceiling, turned about 30 degrees.
const CAMS := {
	"angle": [Vector3(3.3, 2.55, 7.4), Vector3(-0.9, 0.75, -1.0), 44.0],
	"angle_left": [Vector3(-3.8, 2.5, 6.5), Vector3(0.7, 0.9, -1.0), 44.0],
	"front": [Vector3(-0.25, 1.8, 8.9), Vector3(-0.25, 1.32, -2.0), 39.0],
	"console": [Vector3(-0.3, 1.9, 1.6), Vector3(-0.3, 1.05, -2.6), 42.0],
	"left": [Vector3(0.6, 1.6, 3.4), Vector3(-3.4, 0.95, -0.4), 44.0],
	"lounge": [Vector3(-1.2, 1.6, 3.2), Vector3(2.9, 0.8, -0.3), 44.0],
	"booth": [Vector3(0.3, 1.55, -0.4), Vector3(0.3, 1.4, -4.5), 50.0],
	"top": [Vector3(-0.25, 9.5, 6.0), Vector3(-0.25, 0.0, -1.2), 42.0],
}

var _building: Node3D
var _room := -1                # which room the lead is in (index into _building.rooms)
var _fade: ColorRect           # blacks the picture out for a moment when he changes room
var _actor: Node3D             # the lead
var _fry: Node3D               # the second character
var _fry_brain: Node
var _usables: Array = []       # everything E can be used on
var _nearest: Node3D           # the usable thing in reach right now, or null
var _camera: Camera3D
var _cam_name := "follow"
var _cam_at := Vector3.ZERO
var _cam_look := Vector3.ZERO
var _close := false
var _talk: CanvasLayer
var _tag: Label3D              # the name over whatever is nearest
var _hint: Label
var _hud: Label
var _characters: Array[String] = []
var _scripted := false         # screenshot mode: nobody reads the keyboard or wanders
var _shot_path := ""
var _shot_walk := PackedFloat64Array()
var _shot_talk := 0.0
var _shot_rest := 0.0
var _shot_steps := PackedStringArray()


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.08, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.95, 0.9)
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()   # a soft front fill so box faces read as different planes
	sun.rotation_degrees = Vector3(-38, 24, 0)
	sun.light_energy = 0.55
	sun.light_color = Color(1.0, 0.96, 0.9)
	add_child(sun)

	_building = Building.new()
	_building.name = "Building"
	add_child(_building)
	_building.build()

	_actor = _new_actor("Player", START)
	_actor.display_name = "TATTLETALE"       # a working name
	_fry = _new_actor("Fry", Vector3(-1.4, 0, 0.5))
	_fry.set_rig(_rig_dir("fry"))
	_fry.display_name = "LARGE FRY"          # a working name
	_fry.speed = 0.7
	_fry.used.connect(_start_talk)
	_actor.others = [_fry]
	_fry.others = [_actor]
	_fry_brain = Wanderer.new()
	_fry_brain.actor = _fry
	_fry_brain.to_screen = _screen_dir
	_fry_brain.home = (_building.control.AREA as Rect2).grow(-_fry.RADIUS)
	_fry.areas = [_fry_brain.home]            # he stays in the control room
	add_child(_fry_brain)
	_usables = [_fry]
	_usables.append_array(_building.doors)

	_camera = Camera3D.new()
	add_child(_camera)
	_camera.current = true

	for code in range("a".unicode_at(0), "z".unicode_at(0) + 1):
		if ResourceLoader.exists("res://assets/characters/option_%s.png" % char(code)) or FileAccess.file_exists(_rig_dir(char(code)).path_join("rig.json")):
			_characters.append(char(code))

	_tag = Label3D.new()
	_tag.font = FONT
	_tag.font_size = 56
	_tag.pixel_size = 0.0019
	_tag.outline_size = 16
	_tag.modulate = Color("#f6f1e3")
	_tag.outline_modulate = Color.BLACK
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.no_depth_test = true
	_tag.visible = false
	add_child(_tag)

	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(18, 14)
	_hud.add_theme_font_size_override("font_size", 18)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(_hud)
	_hint = Label.new()
	_hint.add_theme_font_override("font", FONT)
	_hint.add_theme_font_size_override("font_size", 24)
	_hint.add_theme_color_override("font_color", Color("#f2d24a"))
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.add_theme_constant_override("outline_size", 8)
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.offset_top = -64.0
	_hint.offset_bottom = -30.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_hint)

	_talk = TalkBox.new()
	add_child(_talk)
	_talk.closed.connect(_end_talk)

	var curtain := CanvasLayer.new()
	curtain.layer = 20
	add_child(curtain)
	_fade = ColorRect.new()
	_fade.color = Color(0.04, 0.03, 0.07, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	curtain.add_child(_fade)

	var who := "e"
	var face := ""
	var mouth := ""
	var wander := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot_path = arg.trim_prefix("--shot=")
		elif arg.begins_with("--cam="):
			_cam_name = arg.trim_prefix("--cam=")
		elif arg.begins_with("--char="):
			who = arg.trim_prefix("--char=")
		elif arg.begins_with("--at="):
			var xz := arg.trim_prefix("--at=").split_floats(",")
			_actor.position = Vector3(xz[0], 0, xz[1])
		elif arg.begins_with("--fry-at="):
			var xz := arg.trim_prefix("--fry-at=").split_floats(",")
			_fry.position = Vector3(xz[0], 0, xz[1])
		elif arg.begins_with("--walk="):   # x,y,seconds: walk that way on screen before the shot
			_shot_walk = arg.trim_prefix("--walk=").split_floats(",")
		elif arg == "--no-ceiling":
			_building.control.ceiling.visible = false
		elif arg == "--no-actor":
			_actor.visible = false
		elif arg.begins_with("--face="):
			face = arg.trim_prefix("--face=")
		elif arg.begins_with("--mouth="):
			mouth = arg.trim_prefix("--mouth=")
		elif arg == "--close":
			_close = true
		elif arg == "--wander":
			wander = true
		elif arg.begins_with("--rest="):   # stand still for this long after the walk
			_shot_rest = float(arg.trim_prefix("--rest="))
		elif arg.begins_with("--talk="):   # move his mouth for this long before the shot
			_shot_talk = float(arg.trim_prefix("--talk="))
		elif arg.begins_with("--do="):
			_shot_steps = arg.trim_prefix("--do=").split(",")
		elif arg == "--check-faces":       # list surfaces lying exactly on one another (they flicker)
			_building.show_from(0)
			var found: Array = FlickerCheck.find(_building)
			var seen := {}
			for line: String in found:
				if not seen.has(line):
					seen[line] = true
					print("[shot] faces: ", line)
			print("[shot] faces: %d overlapping pairs" % seen.size())
	_set_character(who)
	_actor.areas = _building.walk_areas()
	_room = _building.room_at(_actor.position.z)
	_building.show_from(_room)
	if _actor.face and face != "":
		_actor.face.set_expression(face, true)
	if _actor.face and mouth != "":
		_actor.face.hold_mouth(mouth)
	_set_camera(_cam_name)
	if _shot_path != "":
		_scripted = true
		_fry_brain.frozen = not wander
		_hud.visible = false
		_take_shot.call_deferred()


func _new_actor(node_name: String, at: Vector3) -> Node3D:
	var actor: Node3D = PaperActor.new()
	actor.name = node_name
	actor.obstacles = _building.obstacles
	actor.position = at
	add_child(actor)
	return actor


func _rig_dir(folder: String) -> String:
	return "res://assets/characters/%s" % folder


func _set_character(letter: String) -> void:
	var path := "res://assets/characters/option_%s.png" % letter
	_actor.height = 1.8 if letter in ["a", "b"] else 1.55   # the stumpy designs read better shorter
	# A character with loose face parts has its own folder; the rest are one drawing.
	if FileAccess.file_exists(_rig_dir(letter).path_join("rig.json")) and _actor.set_rig(_rig_dir(letter)):
		pass
	elif ResourceLoader.exists(path):
		_actor.set_art(load(path))
	else:
		push_warning("No character art at %s" % path)
		var img := Image.create(64, 192, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.9, 0.3, 0.5))
		_actor.set_art(ImageTexture.create_from_image(img))


# ------------------------------------------------------------------- cameras

func _set_camera(cam: String) -> void:
	if not CAMS.has(cam):
		cam = "follow"
	_cam_name = cam
	if cam == "follow":
		_follow(0.0, true)
	else:
		_camera.fov = CAMS[cam][2]
		_camera.look_at_from_position(CAMS[cam][0], CAMS[cam][1])
	if cam == "top":
		_building.control.ceiling.visible = false
	_face_cards()
	if _close:
		_frame_close()


## Each card turns to face wherever the camera stands, so it never looks thin.
func _face_cards() -> void:
	var back := _camera.global_transform.basis.z
	_actor.rotation.y = atan2(back.x, back.z)
	_fry.rotation.y = _actor.rotation.y


## Ease the camera to a place and a point to look at (snap: go there at once).
func _aim(want: Vector3, look: Vector3, fov: float, delta: float, snap: bool) -> void:
	var k := 1.0 if snap else 1.0 - exp(-5.0 * delta)
	_cam_at = _cam_at.lerp(want, k)
	_cam_look = _cam_look.lerp(look, k)
	_camera.fov = lerpf(_camera.fov, fov, k)
	_camera.look_at_from_position(_cam_at, _cam_look)
	_face_cards()


## Keep the camera a fixed step away from him, easing after him as he walks. In
## a conversation it comes in on the two of them instead; it eases there, so
## there is no cut.
func _follow(delta: float, snap := false) -> void:
	var room: Dictionary = _building.rooms[maxi(_room, 0)]
	var want: Vector3 = _actor.position + FOLLOW_OFFSET * float(room["cam_near"])
	var look := _actor.position + Vector3(0, float(room["look_y"]), 0)
	var fov := 40.0
	if _talk and _talk.is_open():
		var mid := (_actor.position + _fry.position) * 0.5
		want = mid + FOLLOW_OFFSET * 0.85
		look = mid + Vector3(0, 0.6, 0)       # low, so they stand clear of the talk box
		fov = 36.0
	want.x = minf(want.x, float(room["cam_max_x"]))
	want.y = float(room["cam_y"]) if fov > 38.0 else 1.9
	_aim(want, look, fov, delta, snap)


## He has walked through a doorway. Black the picture out for a moment, and
## behind it cut away what now stands between the camera and him and move the
## camera to its place for the new room; then bring the picture back.
func _change_room(to: int, instant := false) -> void:
	_room = to
	if instant:
		_building.show_from(to)
		if _cam_name == "follow":
			_follow(0.0, true)
		return
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 0.1)
	tween.tween_callback(func() -> void:
		_building.show_from(to)
		if _cam_name == "follow":
			_follow(0.0, true))
	tween.tween_property(_fade, "color:a", 0.0, 0.22)


## The close-up: head to waist, from the same side as the room camera.
func _frame_close() -> void:
	var away: Vector3 = FOLLOW_OFFSET if _cam_name == "follow" else CAMS[_cam_name][0] - CAMS[_cam_name][1]
	away.y = 0.0
	away = away.normalized()
	var chest := _actor.position + Vector3(0, _actor.height * 0.6, 0)
	_camera.fov = 30.0
	_camera.look_at_from_position(chest + away * 2.5 + Vector3(0, 0.2, 0), chest)


## Screen direction (x right, y towards the viewer) to a direction on the floor.
func _floor_dir(screen: Vector2) -> Vector2:
	var cam := _camera.global_transform.basis
	var right := Vector2(cam.x.x, cam.x.z).normalized()
	var near := Vector2(cam.z.x, cam.z.z).normalized()
	return right * screen.x + near * screen.y


## And back: a direction on the floor as it looks on screen.
func _screen_dir(floor: Vector2) -> Vector2:
	var cam := _camera.global_transform.basis
	return Vector2(floor.dot(Vector2(cam.x.x, cam.x.z).normalized()), floor.dot(Vector2(cam.z.x, cam.z.z).normalized()))


# ---------------------------------------------------------- using and talking

## Find what E would be used on: the nearest usable thing in its reach. Its name
## goes over it.
func _find_nearest() -> void:
	_nearest = null
	var best := INF
	if not _talk.is_open():
		for thing: Node3D in _usables:
			var gap: Vector3 = thing.use_spot() - _actor.position
			gap.y = 0.0
			if gap.length() <= thing.use_reach and gap.length() < best:
				best = gap.length()
				_nearest = thing
	_tag.visible = _nearest != null
	_hint.visible = _nearest != null
	if _nearest:
		_tag.text = _nearest.use_name()
		_tag.position = _nearest.label_spot()
		_hint.text = "E   TALK" if _nearest == _fry else "E   " + _nearest.use_name()


func _use_nearest() -> void:
	if _nearest and not _talk.is_open():
		_nearest.use(_actor)


func _start_talk(_by: Node3D) -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/talk_fry.json"))
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("Could not read talk_fry.json")
		return
	_fry_brain.frozen = true
	# They turn side-on to face each other.
	var across := _screen_dir(Vector2(_fry.position.x - _actor.position.x, _fry.position.z - _actor.position.z)).x
	_actor.face_side(across)
	_fry.face_side(-across)
	_talk.start(data, _actor, _fry)


func _end_talk() -> void:
	_fry_brain.frozen = _scripted


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if not _scripted and not _talk.is_open():
		dir = Vector2(
			Input.get_axis("ui_left", "ui_right") + float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
			Input.get_axis("ui_up", "ui_down") + float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	_actor.areas = _building.walk_areas()      # doorways open and shut
	_actor.walk(_floor_dir(dir), dir, delta)
	_fry_brain.tick(delta)
	var now: int = _building.room_at(_actor.position.z)
	if now != _room:
		_change_room(now)
	if _close:
		_frame_close()
	elif _cam_name == "follow":
		_follow(delta)
	_find_nearest()
	if _actor.face:
		if not _talk.is_open() and not _scripted:
			_actor.face.talking = Input.is_physical_key_pressed(KEY_SPACE)
			if _actor.face.talking:
				_actor.show_face()
		_hud.text = "face: %s    Z / X change   hold Space to move his mouth   F close-up" % _actor.face.expression
	else:
		_hud.text = "this drawing has its face baked in (5 has loose face parts)"


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo or _talk.is_open():
		return
	match event.physical_keycode:
		KEY_E:
			_use_nearest()
			get_viewport().set_input_as_handled()    # or the same press would also answer the talk box it just opened
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			var pick: int = event.physical_keycode - KEY_1
			if pick < _characters.size():
				_set_character(_characters[pick])
		KEY_TAB:
			var names: Array = ["follow"] + CAMS.keys()
			_building.control.ceiling.visible = true
			_set_camera(names[(names.find(_cam_name) + 1) % names.size()])
		KEY_C:
			_building.control.ceiling.visible = not _building.control.ceiling.visible
		KEY_Z, KEY_X:
			if _actor.face:
				var faces: Array = _actor.face.names()
				var step := 1 if event.physical_keycode == KEY_X else -1
				_actor.show_face()
				_actor.face.set_expression(faces[posmod(faces.find(_actor.face.expression) + step, faces.size())])
		KEY_F:
			_close = not _close
			_set_camera(_cam_name)
		KEY_F8:
			DirAccess.make_dir_recursive_absolute("user://shots")
			_save_frame("user://shots/studio_%d.png" % Time.get_ticks_msec())
		KEY_ESCAPE:
			get_tree().quit()


# ------------------------------------------------------------- screenshot mode

func _save_frame(path: String) -> void:
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("[shot] %s %s" % ["saved" if err == OK else "FAILED", path])


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _take_shot() -> void:
	if _shot_walk.size() == 3:
		var screen := Vector2(_shot_walk[0], _shot_walk[1])
		for i in int(_shot_walk[2] * 60.0):
			_actor.walk(_floor_dir(screen), screen, 1.0 / 60.0)
		for i in int(_shot_rest * 60.0):
			_actor.walk(Vector2.ZERO, Vector2.ZERO, 1.0 / 60.0)
		print("[shot] walked to %.2f, %.2f" % [_actor.position.x, _actor.position.z])
	for step in _shot_steps:
		var bits := step.split(":")
		match bits[0]:
			"use":
				_find_nearest()
				print("[shot] use: %s" % (_nearest.use_name() if _nearest else "nothing in reach"))
				_use_nearest()
			"wait":
				await _wait(float(bits[1]))
			"hover":
				_talk.hover(int(bits[1]))
			"pick":
				print("[shot] pick: %s" % _talk.options()[int(bits[1])]["say"])
				_talk.pick(int(bits[1]))
			"next":
				_talk.advance()
			"clickbox":     # a left click landing on the talk box
				var click := InputEventMouseButton.new()
				click.button_index = MOUSE_BUTTON_LEFT
				click.pressed = true
				_talk._on_box_input(click)
			"go":
				var to := Vector2(float(bits[1]), float(bits[2]))
				_actor.areas = _building.walk_areas()
				for i in 480:
					var gap := to - Vector2(_actor.position.x, _actor.position.z)
					if gap.length() < 0.06:
						break
					_actor.walk(gap.normalized(), _screen_dir(gap.normalized()), 1.0 / 60.0)
				print("[shot] went to %.2f, %.2f" % [_actor.position.x, _actor.position.z])
			"frywalk":
				var way := Vector2(float(bits[1]), float(bits[2]))
				for i in int(float(bits[3]) * 60.0):
					_fry.walk(_floor_dir(way), way, 1.0 / 60.0)
				print("[shot] fry walked to %.2f, %.2f" % [_fry.position.x, _fry.position.z])
	if _shot_talk > 0.0 and _actor.face:
		_actor.face.talking = true
		var shapes := {}
		var until := Time.get_ticks_msec() + int(_shot_talk * 1000.0)
		while Time.get_ticks_msec() < until:
			await get_tree().process_frame
			shapes[_actor.face.shown_mouth()] = true
		print("[shot] talked through %s" % ", ".join(shapes.keys()))
	set_process(false)
	_change_room(_building.room_at(_actor.position.z), true)
	_fade.color.a = 0.0
	if _close:
		_frame_close()
	elif _cam_name == "follow":
		_follow(0.0, true)
	_find_nearest()
	print("[shot] in the %s; fry at %.2f, %.2f; nearest: %s; window at %s" % [_building.rooms[_room]["name"], _fry.position.x, _fry.position.z, _nearest.use_name() if _nearest else "-", DisplayServer.window_get_position()])
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save_frame(_shot_path)
	get_tree().quit()
