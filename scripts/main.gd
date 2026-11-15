extends Node3D
## Pivot prototype: the lead, and the places he can travel to. The studio
## (building.gd) has a second character who wanders the control room and can be
## talked to; the police station, the courthouse, the crib, the corner store,
## the liquor store, Large Fry's place and the hospital are built from floor
## plans (place.gd, plans/*.gd). You arrive on the street, in front of
## the studio door. Only the place he is at is on show.
##
##   WASD / arrows  walk          E       use whatever is nearest: talk, open a door
##   Shift (hold)   run           Q       what he holds: nothing, pistol, Uzi, AK
##   Right mouse button or Ctrl (hold)    point it (he turns side-on, towards the mouse)
##   1 - 9          swap the lead between the character options
##   Tab            next camera (starts on the one that follows him)
##   C              ceiling on / off
##   Z / X          previous / next expression (characters with loose face parts)
##   Space (hold)   move his mouth          F       close-up on / off
##   F8             save a PNG to user://shots
##   M              the travel list: pick a place and he arrives on the street outside it
##
## It opens on the title screen (title_screen.gd): NEW GAME goes to the choice
## between the angel and the devil (choose_screen.gd) and then to the street
## outside the studio; CONTINUE goes back to the place he was last at.
##   E at the booth microphone: he performs, seen through the control-room glass
##                  with black bars top and bottom; Esc steps away
##
## In a conversation: click a line (it turns yellow under the mouse) or press
## its number; E, Space, Enter or a click moves on.
##
## Screenshot mode (used by tools/shot.py):
##   godot --path popup -- --shot=C:/out.png --cam=angle --char=e [--at=x,z] [--no-ceiling]
##         [--place=police|court|crib|store|liquor|fry|hospital] [--room=NAME] [--check-walk]
##         [--face=angry] [--mouth=mouth_ah] [--close] [--talk=seconds]
##         [--walk=x,y,seconds] [--rest=seconds] [--fry-at=x,z] [--wander]
##         [--do=step,step,...] [--check-faces] [--eye=x,y,z,x,y,z]
##         [--title] [--settings] [--choose] [--choose=angel|devil]
##         [--lineup=weapon:rig:pose+pose+...]   a row of one character on a plain backdrop, one for each pose,
##             to judge how things are held: --lineup=ak:e:sc+sa+fc (weapon may be none). A pose is two or three
##             letters: s side, f front, b back; then c carrying, a pointing it; then m mirrored (facing left),
##             w walking, r running. So sam is side-on, pointing it to the left; fcr is running at the camera.
##         [--strip=weapons:rigs:views[:frames]]   frames through one run cycle, side by side, to judge the sprint
##             (run_strip.gd): --strip=none+ak:e:s+f+b:8 writes <shot>_e_none_s.png and so on beside the shot.
##   Steps run in order after the walk: use (press E), wait:seconds, frames:n, hover:n,
##   pick:n, next (E in a conversation), clickbox (click the talk box), walk:x:y:seconds (hold an arrow key:
##   a direction on screen), go:x:z (walk straight to that spot on
##   the floor), frywalk:x:y:seconds (walk the other character on screen), travel (open the travel list),
##   travelhover:n, travelpick:n, key:name (a real key press: key:M, key:Escape, key:1),
##   outfit:slot=item[#rrggbb],slot=item... (someone whose clothes are layers: outfit:jacket=hoodie,hat=none; outfit: alone undoes it),
##   stand:id (stand him at the use point with that id: stand:outfit:hat, stand:sleep),
##   weapon:name (pistol, uzi, ak, or none), aim:1 / aim:0, aimat:x:y (the red cross at that screen spot), sprint:1 / sprint:0,
##   face:front|side|back|left (turn him without walking; left is side-on, mirrored),
##   wear:piece:colour (wear:hat:#cc2222; wear: alone puts his own clothes back),
##   arm:who:weapon[:aim] (give someone else here a weapon: arm:TRE:ak:aim), day:n (make it day n),
##   expr:name or expr:who:name (an expression set as the game sets one, unlike --face: a moment such as a laugh
##   settles into an open-eyed face after paper_face.gd's SETTLE; expr:CHUY:calm for someone else here).

const Building := preload("res://scripts/building.gd")
const Place := preload("res://scripts/place.gd")
## Each place's plan, loaded when he first goes there (so a plan that does not compile spoils only its own place).
const PLANS := {
	"police": "res://scripts/plans/police.gd",
	"court": "res://scripts/plans/court.gd",
	"crib": "res://scripts/plans/crib.gd",
	"store": "res://scripts/plans/store.gd",
	"liquor": "res://scripts/plans/liquor.gd",
	"fry": "res://scripts/plans/fry.gd",
	"hospital": "res://scripts/plans/hospital.gd",
	"park": "res://scripts/plans/park.gd",
	"park2": "res://scripts/plans/park2.gd",
	"street": "res://scripts/plans/street.gd",
	"bea": "res://scripts/plans/bea.gd",
	"clothes": "res://scripts/plans/clothes.gd",
}
const FlickerCheck := preload("res://scripts/flicker_check.gd")
const PaperActor := preload("res://scripts/paper_actor.gd")
const Wanderer := preload("res://scripts/wanderer.gd")
const TalkBox := preload("res://scripts/talk_box.gd")
const TravelMenu := preload("res://scripts/travel_menu.gd")
const TitleScreen := preload("res://scripts/title_screen.gd")
const ChooseScreen := preload("res://scripts/choose_screen.gd")
const FONT := preload("res://assets/fonts/Bungee-Regular.ttf")   # Pen Lucy's display font
const RunStrip := preload("res://scripts/run_strip.gd")       # --strip: frames through a run cycle
const FaceCheck := preload("res://scripts/face_check.gd")     # --check-faces: nobody rests with eyes that cannot blink

## The follow camera keeps this far from him, off to the right. It may not go
## past the right wall of the room he is in (each room says how far) or rise to
## the ceiling, or they hide the room.
const FOLLOW_OFFSET := Vector3(2.3, 0.0, 4.6)

const LEAD_SPEED := 1.25          # the lead walks this much faster than the plain walk (paper_actor.gd's WALK_SPEED)
const BAR := 0.12                 # each black bar of a performance, as a fraction of the screen's height
const PERFORM_ROOM := 2           # a performance is watched from the control room
const MOODS := ["focused", "preachy", "smug", "shout", "happy"]     # his face changes every eight beats
const WEAPONS := ["", "pistol", "uzi", "ak"]      # Q goes round these
const Crosshair := preload("res://scripts/crosshair.gd")
const PlayerState := preload("res://scripts/player_state.gd")
const AIM_SIDE := 0.96      # radians: the cross this far above or below level (55 degrees) is still "to the side"
const AIM_AWAY := false     # turn his back to aim at a cross well above him. Off: that pose (a gun held up beside his head) reads as
                            # pointing at the sky, not away from us, so he stays side-on and tips it up as far as AIM_TIP
const AIM_TIP := 0.6        # ...and side-on he tips what he holds up or down no further than this

## What is on the racks of the clothing store: the colours each piece of
## clothing comes in. E at a rack (a use point "outfit:<piece>") takes the next
## one; after the last he is back in what he was drawn in. A jacket colour
## ending in + has long sleeves. The people of the neighbourhood dress from the
## same racks, differently each day (_dress_for_day).
const WARDROBE := {
	"hat": ["#c62828", "#1c1c22", "#f2c230", "#2e7d32", "#f4f1e8", "#7b3fa0", "#e8731c"],
	"jacket": ["#b3261e", "#b3261e+", "#22252b", "#22252b+", "#2e7d32", "#d9a514+", "#6a3d9a", "#e9e4d6+", "#0e7c86"],
	"shirt": ["#f2c230", "#d84a3a", "#22252b", "#8fd0c8", "#f4a6b8", "#9ccc65"],
	"trousers": ["#23355c", "#1f1f24", "#c9a567", "#5b6b3a", "#8a8f98", "#7a4a2a"],
	"shoes": ["#f4f1e8", "#1c1c22", "#c62828", "#2a5caa", "#7a4a2a"],
}

const SAVE := "user://save.json"              # where the game has got to: {"side", "place"}
const SETTINGS := "user://settings.json"      # {"fullscreen"}

## The travel list (M). Each place says where he arrives (its `arrive`). A row
## with "built": false is listed but cannot be picked.
const PLACES := [
	{"id": "studio", "name": "THE BACK ROOM", "note": "RECORDING STUDIO"},
	{"id": "police", "name": "POLICE STATION", "note": "PEN LUCY PRECINCT"},
	{"id": "court", "name": "COURTHOUSE", "note": "DISTRICT COURT"},
	{"id": "crib", "name": "TATTLETALE'S CRIB", "note": "HOME"},
	{"id": "store", "name": "CORNER STORE", "note": "MISS BEA'S CORNER GROCERY"},
	{"id": "liquor", "name": "LIQUOR STORE", "note": "PARKWAY SPIRITS"},
	{"id": "fry", "name": "LARGE FRY'S PLACE", "note": "ARGONNE COURT, APT 1"},
	{"id": "hospital", "name": "HOSPITAL", "note": "EMERGENCY DEPARTMENT"},
	{"id": "park", "name": "PEN LUCY PARK", "note": "THE COURT"},
	{"id": "park2", "name": "LINDEN SQUARE", "note": "THE OLD GREEN"},
	{"id": "street", "name": "ROSE HILL TERRACE", "note": "THE BLOCK"},
	{"id": "bea", "name": "MISS BEA'S HOUSE", "note": "PORCH-FRONT HOUSE"},
	{"id": "clothes", "name": "CLOTHING STORE", "note": "FRESH THREADS"},
]

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

var _building: Node3D          # the place he is at: the studio (building.gd) or a Place
var _sites := {}               # id: the place, once it has been built
var _room := -1                # which room the lead is in (index into _building.rooms)
var _fade: ColorRect           # blacks the picture out for a moment when he changes room
var _actor: Node3D             # the lead
var _fry: Node3D               # the second character
var _fry_brain: Node
var _cast := {}                # place id: the people there, each {"actor", "brain" (or null), "talk" (a file, or "")}
var _talk_with: Node3D         # who he is talking to
var _wander := false           # screenshot mode: let the wanderers wander
var _usables: Array = []       # everything E can be used on
var _nearest: Node3D           # the usable thing in reach right now, or null
var _camera: Camera3D
var _cam_name := "follow"
var _cam_at := Vector3.ZERO
var _cam_look := Vector3.ZERO
var _close := false
var _talk: CanvasLayer
var _cross: Control             # the red cross he aims with (crosshair.gd)
var _travel: CanvasLayer       # the travel list
var _place := "studio"         # which of PLACES he is at
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
var _shot_eye := PackedFloat64Array()   # x, y, z of the camera and x, y, z of what it looks at, for a picture from anywhere
var _performing := false       # he is at the booth microphone (E there); Esc steps away
var _perform_time := 0.0       # seconds since the show began
var _mood_was := ""            # the face he had before it
var _bars: Array = []          # the two black bars, top and bottom
var _bar := 0.0                # 0 off the screen .. 1 all the way in
var _bar_note: Label
var _mode := "play"            # "title", "choose" (the angel or the devil) or "play"
var _side := ""                # who he listens to: "angel" or "devil", picked at the start of a new game
var _title: CanvasLayer
var _choose: Node3D
var _save_path := SAVE         # a screenshot run may name another file with --save= (it never touches the real one)
var _shot_screen := ""         # screenshot mode: "title", "settings", "choose" or "choose=angel" to photograph that screen
var _env: Environment          # the light on everything: a place may turn it down (place.gd's `ambient`, `sun_energy`)
var _sun: DirectionalLight3D
var _wear := {}                # the clothes he has changed: piece ("hat", "jacket", ...) to Color
var _look := {}                # what he has taken off the racks, if his clothes are layers: slot to {"item": id, "colour": "#rrggbb"}
var _picks := {}               # which colour of WARDROBE each of those is: piece to its number in the list
var _day := 0                  # days since the game began; he sleeps in his own bed to end one
var _state := PlayerState.new()     # his cash, health, rounds, songs and videos (player_state.gd): kept in the save
var _shot_lineup := ""         # screenshot mode: --lineup's weapon:rig:poses
var _shot_strip := ""          # screenshot mode: --strip's weapons:rigs:views:frames


func _ready() -> void:
	var env := Environment.new()
	_env = env
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
	_sun = sun
	sun.rotation_degrees = Vector3(-38, 24, 0)
	sun.light_energy = 0.55
	sun.light_color = Color(1.0, 0.96, 0.9)
	add_child(sun)

	_actor = _new_actor("Player", Vector3.ZERO)
	_actor.display_name = "TATTLETALE"       # a working name
	_actor.speed = LEAD_SPEED
	_fry = _new_actor("Fry", Vector3(-1.4, 0, 0.5))
	_fry.set_rig(_rig_dir("fry"))
	_fry.display_name = "LARGE FRY"          # a working name
	_fry.speed = 0.7
	_fry.reach = 0.5                         # he is wider than the lead
	_fry.used.connect(_start_talk.bind(_fry, "talk_fry.json"))
	_fry.others = [_actor]
	_fry_brain = Wanderer.new()
	_fry_brain.actor = _fry
	_fry_brain.to_screen = _screen_dir
	add_child(_fry_brain)
	_cast["studio"] = [{"actor": _fry, "brain": _fry_brain, "talk": "talk_fry.json"}]
	var first := "studio"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--place="):
			first = arg.trim_prefix("--place=")
	_open_place(first)
	_fry.obstacles = _site("studio").obstacles
	_fry_brain.home = (_site("studio").control.AREA as Rect2).grow_individual(-_fry.reach, -_fry.RADIUS, -_fry.reach, -_fry.RADIUS)
	_fry.areas = [_fry_brain.home]            # he stays in the control room

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
	_cross = Crosshair.new()
	_cross.visible = false
	layer.add_child(_cross)
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

	# The black bars of a performance, under everything else on the screen.
	var cinema := CanvasLayer.new()
	cinema.layer = 5
	add_child(cinema)
	for preset: int in [Control.PRESET_TOP_WIDE, Control.PRESET_BOTTOM_WIDE]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_preset(preset)
		cinema.add_child(bar)
		_bars.append(bar)
	_bar_note = Label.new()
	_bar_note.text = "ESC   STEP AWAY"
	_bar_note.add_theme_font_override("font", FONT)
	_bar_note.add_theme_font_size_override("font_size", 16)
	_bar_note.add_theme_color_override("font_color", Color(0.96, 0.94, 0.89))
	_bar_note.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_bar_note.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bar_note.offset_top = -46.0
	_bar_note.offset_bottom = -20.0
	_bar_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar_note.modulate.a = 0.0
	cinema.add_child(_bar_note)

	_talk = TalkBox.new()
	add_child(_talk)
	_talk.closed.connect(_end_talk)
	_travel = TravelMenu.new()
	_travel.set_places(PLACES)
	add_child(_travel)
	_travel.picked.connect(_travel_to)
	_title = TitleScreen.new()
	add_child(_title)
	_title.new_game.connect(_new_game)
	_title.continue_game.connect(_continue_game)
	_title.fullscreen_set.connect(_set_fullscreen)
	_choose = ChooseScreen.new()
	_choose.position = Vector3(0, 300, 0)        # far above the places, with its own camera and backdrop
	add_child(_choose)
	_choose.build(_rig_dir("e"))
	_choose.started.connect(_begin_game)
	_choose.cancelled.connect(_leave_choose)

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
			if _ceiling():
				_ceiling().visible = false
		elif arg.begins_with("--room="):   # stand him in the middle of the room of that name
			_actor.position = _spot_in_room(arg.trim_prefix("--room="))
		elif arg == "--no-actor":
			_actor.visible = false
		elif arg.begins_with("--face="):
			face = arg.trim_prefix("--face=")
		elif arg.begins_with("--mouth="):
			mouth = arg.trim_prefix("--mouth=")
		elif arg == "--close":
			_close = true
		elif arg == "--wander":
			_wander = true
		elif arg.begins_with("--rest="):   # stand still for this long after the walk
			_shot_rest = float(arg.trim_prefix("--rest="))
		elif arg.begins_with("--talk="):   # move his mouth for this long before the shot
			_shot_talk = float(arg.trim_prefix("--talk="))
		elif arg.begins_with("--do="):
			_shot_steps = arg.trim_prefix("--do=").split(",")
		elif arg.begins_with("--eye="):    # x,y,z,x,y,z: put the camera at the first point, looking at the second
			_shot_eye = arg.trim_prefix("--eye=").split_floats(",")
		elif arg.begins_with("--lineup="):
			_shot_lineup = arg.trim_prefix("--lineup=")
		elif arg.begins_with("--strip="):
			_shot_strip = arg.trim_prefix("--strip=")
		elif arg.begins_with("--save="):   # keep the game in this file instead (for trying CONTINUE)
			_save_path = arg.trim_prefix("--save=")
		elif arg == "--title" or arg == "--settings" or arg.begins_with("--choose"):
			_shot_screen = arg.trim_prefix("--")
		elif arg == "--check-walk":        # can every room be walked to, with every door open?
			_check_walk()
		elif arg == "--check-faces":       # list surfaces lying exactly on one another (they flicker)
			_building.show_room(0)
			var found: Array = FlickerCheck.find(_building)
			var seen := {}
			for line: String in found:
				if not seen.has(line):
					seen[line] = true
					print("[shot] faces: ", line)
			print("[shot] faces: %d overlapping pairs" % seen.size())
			FaceCheck.report(_cast.get(_place, []))
	_set_character(who)
	_actor.areas = _building.walk_areas()
	_room = _building.room_at_pos(_actor.position, 0)
	_building.show_room(_room)
	if _actor.face and face != "":
		_actor.face.hold = true          # a still of that face: a moment (a laugh) is kept, not settled
		_actor.face.set_expression(face, true)
	if _actor.face and mouth != "":
		_actor.face.hold_mouth(mouth)
	_set_camera(_cam_name)
	if _shot_path != "":
		_scripted = true
		for id: String in _cast:
			for member: Dictionary in _cast[id]:
				if member["brain"]:
					member["brain"].frozen = not _wander
		_hud.visible = false
		match _shot_screen.get_slice("=", 0):
			"title":
				_show_title()
			"settings":
				_show_title()
				_title._show_settings(true)
			"choose":
				_new_game()
				if _shot_screen.contains("="):
					_choose.choose(_shot_screen.get_slice("=", 1))
		_take_shot.call_deferred()
	else:
		if _read(SETTINGS).get("fullscreen", false):
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_show_title()


func _new_actor(node_name: String, at: Vector3) -> Node3D:
	var actor: Node3D = PaperActor.new()
	actor.name = node_name
	actor.position = at
	add_child(actor)
	return actor


## The place with that id, built the first time it is asked for.
func _site(id: String) -> Node3D:
	if _sites.has(id):
		return _sites[id]
	var site: Node3D
	if id == "studio" or not PLANS.has(id):
		id = "studio"
		site = Building.new()
		add_child(site)
		site.build()
		site.mic.used.connect(_start_perform)
	else:
		site = Place.new()
		add_child(site)
		var plan: GDScript = load(PLANS[id])
		if plan and plan.can_instantiate():
			plan.build(site)
		else:
			push_warning("The plan for %s did not load" % id)
			site.setup(id.to_upper(), 10.0, 8.0)
			site.street(-4.0, 14.0)
			site.arrive = site.pt(5.0, 9.2)
		for portal: Node3D in site.portals:
			portal.used.connect(_teleport)
		for point: Node3D in site.use_points:
			point.used.connect(_use_point)
		_people(id, site)
	site.name = id.capitalize()
	site.visible = false           # _open_place shows the one he is at
	_sites[id] = site
	return site


## Put him at a place: show it, hide the others, and stand him where he arrives.
func _open_place(id: String) -> void:
	_building = _site(id)
	for key: String in _sites:
		_sites[key].visible = _sites[key] == _building
		if _sites[key] == _building:
			_place = key
	_fry.visible = _place == "studio"
	_env.ambient_light_energy = _building.ambient if "ambient" in _building else 0.62
	_sun.light_energy = _building.sun_energy if "sun_energy" in _building else 0.55
	_actor.others = []
	_actor.obstacles = _building.obstacles
	_usables = _building.usables()
	for member: Dictionary in _cast.get(_place, []):
		_actor.others.append(member["actor"])
		if member["talk"] != "":
			_usables.append(member["actor"])
	_actor.position = _building.arrive
	_actor.areas = _building.walk_areas()
	_room = _building.room_at_pos(_actor.position, 0)
	_building.show_room(_room)


## Make the people a place's plan asks for (place.gd's `people`). Each is a
## paper actor standing in its band's node, so it is hidden when that band is.
func _people(id: String, site: Node3D) -> void:
	var cast: Array = []
	for who: Dictionary in site.people:
		var npc: Node3D = PaperActor.new()
		npc.name = String(who["rig"]).capitalize()
		site.node_of(who["band"]).add_child(npc, true)
		npc.set_rig(_rig_dir(who["rig"]))
		npc.position = who["at"]
		npc.display_name = who.get("name", "")
		npc.speed = who.get("speed", 0.7)
		npc.reach = who.get("reach", npc.REACH)
		npc.weapon = who.get("weapon", "")
		npc.aiming = who.get("aiming", false)
		npc.obstacles = site.obstacles
		npc.others = [_actor]
		if npc.face and who.has("face"):
			npc.face.set_expression(who["face"], true)
		var brain: Node = null
		if who.has("roam"):
			brain = Wanderer.new()
			brain.actor = npc
			brain.to_screen = _screen_dir
			brain.home = (who["roam"] as Rect2).grow_individual(-npc.reach, -npc.RADIUS, -npc.reach, -npc.RADIUS)
			brain.frozen = _scripted and not _wander
			npc.areas = [brain.home]
			add_child(brain)
		var talk: String = who.get("talk", "")
		if talk != "":
			npc.used.connect(_start_talk.bind(npc, talk))
		cast.append({"actor": npc, "brain": brain, "talk": talk})
	_cast[id] = cast
	_dress_for_day()


## The studio's ceiling (C and the top camera hide it); null anywhere else.
func _ceiling() -> Node3D:
	return _building.control.ceiling if _place == "studio" else null


## A clear spot near the middle of the room of that name.
func _spot_in_room(room_name: String) -> Vector3:
	for room: Dictionary in _building.rooms:
		if String(room["name"]).to_lower() != room_name.to_lower().replace("_", " "):
			continue
		var area: Rect2 = room.get("areas", [room.get("area", Rect2())])[0]
		var mid := area.get_center()
		var best := mid
		var best_gap := INF
		_actor.areas = _building.walk_areas()
		for ix in int(area.size.x / 0.2) + 1:
			for iz in int(area.size.y / 0.2) + 1:
				var p := area.position + Vector2(ix, iz) * 0.2
				if _actor.can_stand(p) and p.distance_to(mid) < best_gap:
					best_gap = p.distance_to(mid)
					best = p
		return Vector3(best.x, 0, best.y)
	push_warning("No room called %s here" % room_name)
	return _actor.position


## With every door open, flood the floor from where he stands and say how much
## of each room he can reach. A room he cannot reach at all, or mostly cannot,
## has a blocked doorway or a prop in the way.
func _check_walk() -> void:
	for door: Node3D in _building.doors:
		door.set_open(true, true)
	_actor.areas = _building.walk_areas()
	var step := 0.1
	var seen := {}
	var reached := {}
	var queue: Array[Vector2i] = []
	var from := Vector2i(roundi(_actor.position.x / step), roundi(_actor.position.z / step))
	for dx in range(-3, 4):      # start from every clear spot right by him (he may stand between grid points)
		for dz in range(-3, 4):
			queue.append(from + Vector2i(dx, dz))
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		if seen.has(cell):
			continue
		seen[cell] = true
		var p := Vector2(cell.x, cell.y) * step
		if not _actor.can_stand(p):
			continue
		reached[cell] = true
		for way: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			queue.append(cell + way)
		for portal: Node3D in _building.portals:
			var spot: Vector3 = portal.use_spot()
			if p.distance_to(Vector2(spot.x, spot.z)) <= portal.use_reach:
				queue.append(Vector2i(roundi(portal.to.x / step), roundi(portal.to.z / step)))
	var bad := 0
	for room: Dictionary in _building.rooms:
		var r: Rect2 = room.get("rect", room.get("area", Rect2()))
		var can := 0
		var got := 0
		for ix in range(roundi(r.position.x / step), roundi(r.end.x / step)):
			for iz in range(roundi(r.position.y / step), roundi(r.end.y / step)):
				if _actor.can_stand(Vector2(ix, iz) * step):
					can += 1
					if reached.has(Vector2i(ix, iz)):
						got += 1
		var verdict := "ok"
		if got == 0:
			verdict = "NOT REACHED"
		elif got < can * 0.85:
			verdict = "PARTLY CUT OFF"
		if verdict != "ok":
			bad += 1
		print("[shot] walk: %-18s %5.1f of %5.1f sq m  %s" % [room["name"], got * step * step, can * step * step, verdict])
	print("[shot] walk: %d rooms, %d doors, %d with a problem" % [_building.rooms.size(), _building.doors.size(), bad])
	# Is anyone standing in a wall or a prop?
	var misplaced := 0
	for member: Dictionary in _cast.get(_place, []):
		var npc: Node3D = member["actor"]
		if not _actor.can_stand(Vector2(npc.position.x, npc.position.z)):
			misplaced += 1
			print("[shot] people: %s at %.2f, %.2f is IN A WALL OR A PROP" % [npc.name, npc.position.x, npc.position.z])
	print("[shot] people: %d here, %d misplaced" % [_cast.get(_place, []).size(), misplaced])


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
	if not CAMS.has(cam) or _place != "studio":     # the fixed cameras are the studio's
		cam = "follow"
	_cam_name = cam
	if cam == "follow":
		_follow(0.0, true)
	else:
		_camera.fov = CAMS[cam][2]
		_camera.look_at_from_position(CAMS[cam][0], CAMS[cam][1])
	if cam == "top" and _ceiling():
		_ceiling().visible = false
	_face_cards()
	if _close:
		_frame_close()


## Each card turns to face wherever the camera stands, so it never looks thin.
func _face_cards() -> void:
	var back := _camera.global_transform.basis.z
	_actor.rotation.y = atan2(back.x, back.z)
	for member: Dictionary in _cast.get(_place, []):
		member["actor"].rotation.y = _actor.rotation.y


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
		var mid := (_actor.position + _talk_with.position) * 0.5
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
		_building.show_room(to)
		if _cam_name == "follow":
			_follow(0.0, true)
		return
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 0.1)
	tween.tween_callback(func() -> void:
		_building.show_room(to)
		if _cam_name == "follow":
			_follow(0.0, true))
	tween.tween_property(_fade, "color:a", 0.0, 0.22)


## Stairs and the like (portal.gd): black out, put him at the other end, come back.
func _teleport(to: Vector3, instant := false) -> void:
	var land := func() -> void:
		_actor.position = to
		_actor.areas = _building.walk_areas()
		_room = _building.room_at_pos(to, _room)
		_building.show_room(_room)
		if _cam_name == "follow":
			_follow(0.0, true)
	if instant:
		land.call()
		return
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 0.15)
	tween.tween_callback(land)
	tween.tween_interval(0.1)
	tween.tween_property(_fade, "color:a", 0.0, 0.25)


## Go to one of PLACES: the picture blacks out, he is put on the pavement
## outside it facing the camera, and the picture comes back.
func _travel_to(id: String, instant := false) -> void:
	var known := false
	for row: Dictionary in PLACES:
		if row["id"] == id and row.get("built", true):
			known = true
	if not known:
		return
	var arrive := func() -> void:
		_open_place(id)
		_actor.show_face()
		_set_camera(_cam_name)
		_save_game()
	if instant:
		arrive.call()
		return
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 0.18)
	tween.tween_callback(arrive)
	tween.tween_interval(0.15)
	tween.tween_property(_fade, "color:a", 0.0, 0.3)


## The close-up: head to waist, from the same side as the room camera.
func _frame_close() -> void:
	var away: Vector3 = FOLLOW_OFFSET if _cam_name == "follow" else CAMS[_cam_name][0] - CAMS[_cam_name][1]
	away.y = 0.0
	away = away.normalized()
	var chest := _actor.position + Vector3(0, _actor.height * 0.6, 0)
	_camera.fov = 30.0
	_camera.look_at_from_position(chest + away * 2.5 + Vector3(0, 0.2, 0), chest)
	_face_cards()


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

## Doors in a cut-away wall come into view as he nears them (door.gd).
func _show_doors() -> void:
	for door: Node3D in _building.doors:
		door.show_near(_actor.position)


## Find what E would be used on: the nearest usable thing in its reach. Its name
## goes over it.
func _find_nearest() -> void:
	_nearest = null
	var best := INF
	if not _talk.is_open() and not _performing and _mode == "play":
		for thing: Node3D in _usables:
			if not thing.is_visible_in_tree():
				continue
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
		_hint.text = "E   TALK" if _nearest.has_method("face_side") else "E   " + _nearest.use_name()
		if _rack_slot() != "":
			_hint.text += "        C   COLOUR"


## The slot of the rack of clothes he is standing at ("" if he is not at one, or his clothes are not layers).
func _rack_slot() -> String:
	if _nearest == null or not _actor.has_wardrobe() or not "id" in _nearest:
		return ""
	var id := String(_nearest.id)
	return id.trim_prefix("outfit:") if id.begins_with("outfit:") and id != "outfit:reset" else ""


func _use_nearest() -> void:
	if _nearest and not _talk.is_open():
		if _nearest.has_method("set_open") and _scripted:
			_nearest.set_open(not _nearest.is_open, true)     # scripted runs do not wait for the swing
		else:
			_nearest.use(_actor)


## E on someone who has something to say: `file` is their conversation, in assets/data.
func _start_talk(_by: Node3D, npc: Node3D, file: String) -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/" + file))
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("Could not read %s" % file)
		return
	_talk_with = npc
	_set_frozen(npc, true)
	# They turn side-on to face each other.
	var across := _screen_dir(Vector2(npc.position.x - _actor.position.x, npc.position.z - _actor.position.z)).x
	_actor.face_side(across)
	npc.face_side(-across)
	_talk.start(data, _actor, npc)


func _end_talk() -> void:
	_set_frozen(_talk_with, _scripted)


## E at a use point (use_point.gd, place.gd's `use_point`): what happens depends on its id.
##   outfit:<piece>   a rack in the clothing store: the next colour of that piece (hat, jacket, shirt, trousers, shoes)
##   outfit:reset     the mirror: back into what he was drawn in
##   sleep            his bed: the picture blacks out and it is the next day
func _use_point(id: String, _by: Node3D) -> void:
	print("[use] ", id)
	if id == "outfit:reset":
		_picks = {}
		_look = {}
		_dress_lead()
		_save_game()
	elif id.begins_with("outfit:") and _actor.has_wardrobe():
		_next_style(id.trim_prefix("outfit:"))
	elif id.begins_with("outfit:"):
		var piece := id.trim_prefix("outfit:")
		var rack: Array = WARDROBE.get(piece, [])
		if rack.is_empty() or not piece in _actor.clothes():
			return
		var next: int = int(_picks.get(piece, -1)) + 1
		if next >= rack.size():
			_picks.erase(piece)
		else:
			_picks[piece] = next
		_dress_lead()
		_save_game()
	elif id == "sleep":
		_cut_to(func() -> void:
			_day += 1
			_dress_for_day()
			_save_game()
			print("[use] day %d" % _day))


## The styles someone with a wardrobe can have in a slot: the ids of its items, and "" (left off) for a hat or a jacket.
func _styles(who: Node3D, slot: String) -> Array:
	var out := []
	var items: Dictionary = who.wardrobe().get("items", {})
	for id: String in items:
		if String(items[id].get("slot", "")) == slot:
			out.append(id)
	if not out.is_empty() and slot in ["hat", "jacket"]:
		out.append("")
	return out


## The colours an item comes in, as "#rrggbb", the one it was drawn in first.
func _colours_of(who: Node3D, id: String) -> Array:
	var item: Dictionary = who.wardrobe().get("items", {}).get(id, {})
	var out := []
	for rgb: Array in item.get("colours", [item.get("colour", [128, 128, 128])]):
		out.append("#" + Color(float(rgb[0]) / 255.0, float(rgb[1]) / 255.0, float(rgb[2]) / 255.0).to_html(false))
	return out


## A look as PaperActor.wear wants it (the colours as Colors).
func _outfit_of(look: Dictionary) -> Dictionary:
	var out := {}
	for slot: String in look:
		var entry := {"item": String(look[slot].get("item", ""))}
		if look[slot].has("colour"):
			entry["colour"] = Color(String(look[slot]["colour"]))
		out[slot] = entry
	return out


## At a rack: the next style of that piece (a hoodie after the vest; nothing, after the last hat or jacket).
func _next_style(slot: String) -> void:
	var styles := _styles(_actor, slot)
	if styles.is_empty():
		return
	var on := String(_actor.worn().get(slot, {}).get("item", ""))
	_look[slot] = {"item": styles[(styles.find(on) + 1) % styles.size()]}
	_dress_lead()
	_save_game()
	var now := String(_actor.worn()[slot]["item"])
	print("[use] %s: %s" % [slot, _actor.wardrobe()["items"][now].get("name", now) if now != "" else "none"])


## At a rack: the same thing in its next colour.
func _next_colour(slot: String) -> void:
	var on: Dictionary = _actor.worn().get(slot, {})
	var id := String(on.get("item", ""))
	var colours := _colours_of(_actor, id)
	if id == "" or colours.size() < 2:
		return
	var now := "#" + (on["colour"] as Color).to_html(false)
	_look[slot] = {"item": id, "colour": colours[(colours.find(now) + 1) % colours.size()]}
	_dress_lead()
	_save_game()
	print("[use] %s: %s %s" % [slot, id, _look[slot]["colour"]])


## Put the lead in what he has picked off the racks (_look if his clothes are layers, else _picks).
func _dress_lead() -> void:
	if _actor.has_wardrobe():
		_actor.wear(_outfit_of(_look))
		return
	_wear = {}
	for piece: String in _picks:
		var rack: Array = WARDROBE.get(piece, [])
		var n := int(_picks[piece])
		if n < 0 or n >= rack.size():
			continue
		var colour: String = rack[n]
		_wear[piece] = Color(colour.trim_suffix("+"))
		if piece == "jacket" and colour.ends_with("+"):
			_wear["sleeve"] = _wear[piece]
	_actor.set_outfit(_wear)


## Dress everyone for today. On the first day they wear what they were drawn
## in; after that each person takes two or three pieces off the racks, the
## same ones all that day and different ones the next. Only people whose
## drawings know their clothes (outfit.py) change: uniforms stay uniforms.
func _dress_for_day() -> void:
	for id: String in _cast:
		for member: Dictionary in _cast[id]:
			var npc: Node3D = member["actor"]
			if npc.has_wardrobe():       # layers: a different cut as well as colour
				var look := {}
				if _day > 0:
					for slot: String in ["hat", "jacket", "shirt", "trousers", "shoes"]:
						var roll := hash("%s/%s/%d" % [npc.name, slot, _day])
						var styles := _styles(npc, slot)
						if styles.is_empty() or roll % 3 == 0:
							continue                   # this piece is as drawn today
						var style := String(styles[(roll / 3) % styles.size()])
						look[slot] = {"item": style}
						if style != "":
							var colours := _colours_of(npc, style)
							look[slot]["colour"] = colours[(roll / 7) % colours.size()]
				npc.wear(_outfit_of(look))
				continue
			var wear := {}
			if _day > 0:
				for piece: String in npc.clothes():
					var rack: Array = WARDROBE.get(piece, [])
					var roll := hash("%s/%s/%d" % [npc.name, piece, _day])
					if rack.is_empty() or roll % 3 == 0:
						continue                       # this piece is as drawn today
					wear[piece] = Color(String(rack[(roll / 3) % rack.size()]).trim_suffix("+"))
			npc.set_outfit(wear)


## Stop or release whoever walks `npc` about (nothing, for someone who only stands).
func _set_frozen(npc: Node3D, frozen: bool) -> void:
	for member: Dictionary in _cast.get(_place, []):
		if member["actor"] == npc and member["brain"]:
			member["brain"].frozen = frozen


# ------------------------------------------------------- title and new game

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if typeof(data) == TYPE_DICTIONARY else {}


func _write(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))


## Remember where the game has got to, for CONTINUE. A screenshot run never saves.
func _save_game() -> void:
	if _mode == "play" and not (_scripted and _save_path == SAVE):
		_write(_save_path, {"side": _side, "place": _place, "day": _day, "wear": _look if _actor.has_wardrobe() else _picks, "state": _state.to_save()})


## Which screen is up. The places are hidden behind the choice (it has its own
## camera and backdrop) and shown, dimmed by the title's own shade, behind the title.
func _set_mode(mode: String) -> void:
	_mode = mode
	_hud.visible = mode == "play" and not _scripted
	var world := mode != "choose"
	_building.visible = world
	_actor.visible = world
	_fry.visible = world and _place == "studio"
	if world:
		_camera.current = true


## Black the picture out, make the change behind it, bring the picture back.
## (At once in a screenshot run.)
func _cut_to(change: Callable) -> void:
	if _scripted:
		change.call()
		return
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 0.2)
	tween.tween_callback(change)
	tween.tween_interval(0.1)
	tween.tween_property(_fade, "color:a", 0.0, 0.35)


func _show_title() -> void:
	_set_mode("title")
	_title.open(not _read(_save_path).is_empty(), DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)


## NEW GAME: to the angel and the devil.
func _new_game() -> void:
	_cut_to(func() -> void:
		_title.close()
		_set_mode("choose")
		_choose.open())


## Esc on the choice: back to the title.
func _leave_choose() -> void:
	_cut_to(func() -> void:
		_choose.close()
		_show_title())


## START on the choice: the game begins on the street outside the studio.
func _begin_game(side: String) -> void:
	_cut_to(func() -> void:
		_choose.close()
		_side = side
		_day = 0
		_state.reset()
		_picks = {}
		_dress_lead()
		_dress_for_day()
		_set_mode("play")
		_open_place("studio")
		_actor.show_face()
		_set_camera("follow")
		_save_game())


## CONTINUE: back to the place he was last at, listening to whoever he chose.
func _continue_game() -> void:
	var data := _read(_save_path)
	_cut_to(func() -> void:
		_title.close()
		_side = String(data.get("side", ""))
		_day = int(data.get("day", 0))
		_state.from_save(PlayerState._dict(data.get("state")))
		_picks = {}
		_look = {}
		var kept = data.get("wear", {})
		if typeof(kept) == TYPE_DICTIONARY:
			for piece: String in kept:
				if typeof(kept[piece]) == TYPE_DICTIONARY:      # layers: an item and perhaps a colour
					_look[piece] = kept[piece]
				else:
					_picks[piece] = int(kept[piece])
		_dress_lead()
		_set_mode("play")
		var id := String(data.get("place", "studio"))
		_open_place(id if PLANS.has(id) else "studio")
		_actor.show_face()
		_set_camera("follow"))


func _set_fullscreen(on: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_MAXIMIZED)
	var settings := _read(SETTINGS)
	settings["fullscreen"] = on
	_write(SETTINGS, settings)


# ------------------------------------------------------------ at the microphone

## He steps up to the booth microphone (E on it). The picture blacks out for
## a moment and comes back on him seen from the control room, through the
## glass, with black bars top and bottom; he performs until Esc.
func _start_perform(spot: Vector3) -> void:
	if _performing or _talk.is_open():
		return
	_performing = true
	_perform_time = 0.0
	var begin := func() -> void:
		_actor.position = spot
		_actor.performing = true
		_actor.show_face()
		if _actor.face:
			_mood_was = _actor.face.expression
			_actor.face.set_expression(MOODS[0])
			_actor.face.talking = true
		_building.show_room(PERFORM_ROOM)
		_perform_cam(0.0)
	if _scripted:
		begin.call()
		return
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 0.18)
	tween.tween_callback(begin)
	tween.tween_interval(0.1)
	tween.tween_property(_fade, "color:a", 0.0, 0.4)


## Esc: he steps back from the microphone and the camera goes back to following him.
func _stop_perform() -> void:
	if not _performing or not _actor.performing:
		return
	var finish := func() -> void:
		_performing = false
		_actor.performing = false
		if _actor.face:
			_actor.face.talking = false
			_actor.face.set_expression(_mood_was if _mood_was != "" else "neutral")
		_room = _building.room_at_pos(_actor.position, _room)
		_building.show_room(_room)
		_set_camera(_cam_name)
	if _scripted:
		finish.call()
		return
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 0.18)
	tween.tween_callback(finish)
	tween.tween_interval(0.1)
	tween.tween_property(_fade, "color:a", 0.0, 0.3)


## The camera for a performance: in the control room, over the desk and close
## to the window, a little above his head, drifting slowly from side to side
## and always on him.
func _perform_cam(delta: float) -> void:
	_perform_time += delta
	var spot: Vector3 = _building.mic.to
	_cam_at = Vector3(spot.x + 0.1 + 0.5 * sin(_perform_time * 0.5), 1.62 + 0.03 * sin(_perform_time * 0.37), _building.control.Z0 + 0.95)
	_cam_look = spot + Vector3(0.1, 0.95, 0.0)
	_camera.fov = 42.0
	_camera.look_at_from_position(_cam_at, _cam_look)
	_face_cards()
	if _actor.face:
		var mood: String = MOODS[int(_perform_time / (8.0 * _actor.BEAT)) % MOODS.size()]
		if _actor.face.expression != mood:
			_actor.face.set_expression(mood)


## Slide the black bars in or out, and fade the corner text with them.
func _show_bars(delta: float) -> void:
	_bar = move_toward(_bar, 1.0 if _performing and _actor.performing else 0.0, delta * 1.6)
	var h := get_viewport().get_visible_rect().size.y * BAR * smoothstep(0.0, 1.0, _bar)
	(_bars[0] as ColorRect).offset_bottom = h
	(_bars[1] as ColorRect).offset_top = -h
	_bar_note.modulate.a = 0.55 * _bar
	_hud.modulate.a = 1.0 - _bar


func _process(delta: float) -> void:
	if _mode == "choose":            # the choice runs itself; the places are hidden
		return
	var dir := Vector2.ZERO
	if not _scripted and not _talk.is_open() and not _travel.is_open() and not _performing and _mode == "play":
		dir = Vector2(
			Input.get_axis("ui_left", "ui_right") + float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
			Input.get_axis("ui_up", "ui_down") + float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	_actor.areas = _building.walk_areas()      # doorways open and shut
	if not _scripted:
		var free: bool = not _talk.is_open() and not _travel.is_open() and not _performing and _mode == "play"
		_actor.sprinting = free and Input.is_physical_key_pressed(KEY_SHIFT)
		# The right mouse button brings up the cross and he points what he holds at it; Ctrl points it the way he is facing.
		var mouse: bool = free and _actor.weapon != "" and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		if mouse:
			_aim_at(get_viewport().get_mouse_position())
		else:
			_aim_off()
			_actor.aiming = free and Input.is_physical_key_pressed(KEY_CTRL)
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if mouse else Input.MOUSE_MODE_VISIBLE
	_actor.walk(_floor_dir(dir), dir, delta)
	for member: Dictionary in _cast.get(_place, []):
		if member["brain"]:
			member["brain"].tick(delta)
		else:
			member["actor"].walk(Vector2.ZERO, Vector2.ZERO, delta)
	for watcher: Node3D in _building.watchers:
		watcher.watch(_actor.position, delta)
	var now: int = _building.room_at_pos(_actor.position, _room)
	if _performing:
		if _actor.performing:      # not until the picture has blacked out
			_perform_cam(delta)
	elif now != _room:
		if _building.cut_of(now) != _building.cut_of(_room):
			_change_room(now)      # a different cut of the building: fade
		else:
			_room = now            # the room next door: the camera just eases over
	if _performing:
		pass
	elif _close:
		_frame_close()
	elif _cam_name == "follow":
		_follow(delta)
	_find_nearest()
	_show_doors()
	_show_bars(delta)
	if _actor.face:
		if not _talk.is_open() and not _scripted and not _performing:
			_actor.face.talking = Input.is_physical_key_pressed(KEY_SPACE)
			if _actor.face.talking:
				_actor.show_face()
		_hud.text = "day %d   M travel   Shift run   Q weapon (%s)   right mouse: point it    face: %s   Z / X change   Space: mouth   F close-up%s" % [_day + 1, "none" if _actor.weapon == "" else _actor.weapon, _actor.face.expression, "" if _side == "" else "    listening to the %s" % _side]
	else:
		_hud.text = "M travel    this drawing has its face baked in (5 has loose face parts)"


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo or _talk.is_open() or _travel.is_open() or _mode != "play":
		return
	if _performing:                 # nothing but Esc while he is at the microphone
		if event.physical_keycode == KEY_ESCAPE:
			_stop_perform()
		get_viewport().set_input_as_handled()
		return
	match event.physical_keycode:
		KEY_M:
			_travel.open(_place)
			get_viewport().set_input_as_handled()    # or the same press would close the list it just opened
		KEY_E:
			_use_nearest()
			get_viewport().set_input_as_handled()    # or the same press would also answer the talk box it just opened
		KEY_C:                      # at a rack of clothes: the same thing in its next colour; in the studio, the ceiling
			var rack := _rack_slot()
			if rack != "":
				_next_colour(rack)
			elif _ceiling():
				_ceiling().visible = not _ceiling().visible
		KEY_Q:
			_actor.weapon = WEAPONS[(WEAPONS.find(_actor.weapon) + 1) % WEAPONS.size()]
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			var pick: int = event.physical_keycode - KEY_1
			if pick < _characters.size():
				_set_character(_characters[pick])
		KEY_TAB:
			var names: Array = ["follow"] + CAMS.keys()
			if _ceiling():
				_ceiling().visible = true
			_set_camera(names[(names.find(_cam_name) + 1) % names.size()])
		KEY_Z, KEY_X:
			if _actor.face:
				var faces: Array = _actor.face.names()
				var step := 1 if event.physical_keycode == KEY_X else -1
				_actor.show_face()
				_actor.face.set_expression(faces[posmod(faces.find(_actor.face.asked) + step, faces.size())])
		KEY_F:
			_close = not _close
			_set_camera(_cam_name)
		KEY_F8:
			DirAccess.make_dir_recursive_absolute("user://shots")
			_save_frame("user://shots/studio_%d.png" % Time.get_ticks_msec())
		KEY_ESCAPE:
			get_tree().quit()


# ------------------------------------------------------------- screenshot mode

## A row of one character, one for each pose asked for, on a plain backdrop far
## above the places, seen square-on. See --lineup at the top.
## He points what he holds at `cross`, a spot on the screen, and the red cross is drawn there. From his chest:
## within AIM_SIDE of level it is to the left or right, tipped up or down that much (as far as AIM_TIP);
## steeper than that, up the screen is away from the camera and down it is towards it.
func _aim_at(cross: Vector2) -> void:
	var from := _camera.unproject_position(_actor.global_position + Vector3(0.0, _actor.height * 0.55, 0.0))
	var to := cross - from
	var rise := atan2(-to.y, absf(to.x))                       # how far above level, seen on the screen
	var edge := AIM_SIDE + (0.1 if _actor.aim_way == "" else -0.1)      # a little sticky, so it does not flicker at the edge
	_actor.aiming = true
	_actor.aim_way = "" if absf(rise) < edge or (rise > 0.0 and not AIM_AWAY) else ("away" if rise > 0.0 else "toward")
	_actor.aim_to = signf(to.x)
	_actor.aim_pitch = clampf(rise, -AIM_TIP, AIM_TIP) if _actor.aim_way == "" else 0.0
	_actor.aim_lean = atan2(to.x, -to.y)          # pointing away: how far the cross is to the right of straight up
	_cross.at = cross
	_cross.loose = move_toward(_cross.loose, 1.0 if _actor.sprinting else 0.0, 0.2)
	_cross.visible = true


## The cross goes; he points it nowhere in particular.
func _aim_off() -> void:
	_actor.aim_way = ""
	_actor.aim_pitch = 0.0
	_actor.aim_to = 0.0
	_cross.visible = false


func _lineup(spec: String) -> void:
	var bits := spec.split(":")
	var rigs := (bits[1] if bits.size() > 1 else "e").split(",")        # one for all, or one for each pose
	var poses := (bits[2] if bits.size() > 2 else "sc+sa+fc").split("+")
	var origin := Vector3(0, 600, 0)
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.56, 0.6, 0.66)
	grey.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	Kit.box(self, Vector3(60, 30, 0.1), origin + Vector3(0, 0, -1.2), grey)
	var floor_look := StandardMaterial3D.new()
	floor_look.albedo_color = Color(0.44, 0.47, 0.52)
	floor_look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	Kit.box(self, Vector3(60, 0.1, 6), origin + Vector3(0, -0.05, 0), floor_look)
	var gap := 2.5
	var tall := 1.8
	for i in poses.size():
		var pose: String = poses[i]
		var who: Node3D = PaperActor.new()
		add_child(who)
		if not who.set_rig(_rig_dir(rigs[i % rigs.size()])):
			continue
		if who.has_wardrobe() and not _look.is_empty():      # dressed as the outfit: steps said
			who.wear(_outfit_of(_look))
		tall = maxf(tall, who.height + 0.25)
		var spot := origin + Vector3((i - (poses.size() - 1) * 0.5) * gap, 0, 0)
		who.position = spot
		who.areas = [Rect2(-99, -99, 198, 198)]
		who.weapon = "" if bits[0] == "none" else bits[0]
		who.aiming = pose.substr(1, 1) in ["a", "p"]
		var way: String = {"s": "side", "f": "front", "b": "back"}.get(pose.substr(0, 1), "front")
		if pose.substr(1, 1) == "p":        # pointed along the line of sight: at the camera from the front, away from the back
			who.aim_way = "toward" if way == "front" else "away"
		who.aim_pitch = 0.5 if pose.contains("u") else (-0.5 if pose.contains("d") else 0.0)       # side-on: up, down
		var mirrored := pose.contains("m")
		who.face_way(way, mirrored)
		for f in 90:
			who.walk(Vector2.ZERO, Vector2.ZERO, 1.0 / 60.0)
		if pose.contains("w") or pose.contains("r"):
			who.sprinting = pose.contains("r")
			var dir := Vector2(-1.0 if mirrored else 1.0, 0.0) if way == "side" else Vector2(0.0, 1.0 if way == "front" else -1.0)
			for f in (47 if pose.contains("w") else 38):
				who.walk(dir, dir, 1.0 / 60.0)
		who.position = spot
	_camera.fov = 24.0
	var wide := poses.size() * gap
	var far := maxf(wide / (16.0 / 9.0), tall) * 0.5 / tan(deg_to_rad(12.0))
	_camera.look_at_from_position(origin + Vector3(0, tall * 0.5 - 0.08, far), origin + Vector3(0, tall * 0.5 - 0.08, 0))
	_tag.visible = false
	_hint.visible = false


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
		if not step.contains(":") and step.contains("="):      # outfit:jacket=hoodie,shirt=tee: the pieces after the first
			step = "outfit:" + step
		var bits := step.split(":")
		match bits[0]:
			"outfit":       # outfit:slot=item or outfit:slot=item#rrggbb or outfit:slot=none ; outfit: alone puts his own clothes back
				if bits.size() < 2 or not bits[1].contains("="):
					_look = {}
				else:
					var piece := bits[1].split("=")
					var want := piece[1].split("#")
					_look[piece[0]] = {"item": "" if want[0] == "none" else want[0]}
					if want.size() > 1:
						_look[piece[0]]["colour"] = "#" + want[1]
				_dress_lead()
				print("[shot] outfit: %s" % [_actor.worn() if _actor.has_wardrobe() else "this character's clothes are not layers"])
			"stand":        # stand:outfit:hat puts him at the use point with that id (a rack, the bed)
				var want := step.trim_prefix("stand:")
				for thing in _usables:
					if is_instance_valid(thing) and "id" in thing and String(thing.id) == want:
						_actor.global_position = Vector3(thing.use_spot().x, _actor.global_position.y, thing.use_spot().z)
						print("[shot] stand: at %s" % want)
			"use":
				_find_nearest()
				print("[shot] use: %s" % (_nearest.use_name() if _nearest else "nothing in reach"))
				_use_nearest()
			"wait":
				await _wait(float(bits[1]))
			"choose":       # choose:angel or choose:devil (or choose: to let go), on the new-game screen
				_choose.choose(bits[1] if bits.size() > 1 else "")
				print("[shot] chose: %s" % _choose.chosen)
			"continue":     # pick CONTINUE on the title screen
				_continue_game()
				print("[shot] continued: mode %s, side %s, place %s" % [_mode, _side, _place])
			"blink":        # blink:side:amount: hold that one's eyes part shut (0 open .. 1 shut), for a picture
				_choose._blinks[bits[1]]["hold"] = float(bits[2])
			"pose":         # pose:seconds: stop the choice screen's clock at that moment, for a picture
				_choose._time = float(bits[1])
				_choose._held = true
			"start":        # press START there
				_choose.start()
				print("[shot] started: mode %s, side %s, place %s" % [_mode, _side, _place])
			"frames":       # frames:n: let n frames go by (to catch something part-way through)
				for i in int(bits[1]):
					await get_tree().process_frame
				print("[shot] after %s frames: talk box open %.2f" % [bits[1], _talk.open_amount()])
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
			"walk":         # walk:x:y:seconds, a direction on screen as the arrow keys give it (x right, y towards the viewer)
				var held := Vector2(float(bits[1]), float(bits[2]))
				for i in int(float(bits[3]) * 60.0):
					_actor.areas = _building.walk_areas()
					_actor.walk(_floor_dir(held), held, 1.0 / 60.0)
				print("[shot] walked to %.2f, %.2f" % [_actor.position.x, _actor.position.z])
			"key":          # a real key press, through the game's own input handling: key:M, key:Escape, key:1
				var press := InputEventKey.new()
				press.physical_keycode = OS.find_keycode_from_string(bits[1])
				press.keycode = press.physical_keycode
				press.pressed = true
				Input.parse_input_event(press)
				await _wait(0.15)
				print("[shot] key %s: travel list %s, talk %s, performing %s, at %.2f, %.2f" % [bits[1], "open" if _travel.is_open() else "shut", "open" if _talk.is_open() else "shut", _performing, _actor.position.x, _actor.position.z])
			"travel":
				_travel.open(_place)
			"travelhover":
				_travel.hover(int(bits[1]))
			"travelpick":
				print("[shot] travel: %s" % PLACES[int(bits[1])]["name"])
				_travel.pick(int(bits[1]))
				await _wait(0.9)
				print("[shot] arrived at %.2f, %.2f; list open: %s" % [_actor.position.x, _actor.position.z, _travel.is_open()])
			"weapon":       # weapon:pistol, weapon:uzi, weapon:ak, weapon:none
				_actor.weapon = "" if bits[1] == "none" else bits[1]
			"aim":          # aim:1 points it, aim:0 lowers it
				_actor.aiming = bits[1] == "1"
				if not _actor.aiming:
					_aim_off()
			"aimat":        # aimat:x:y puts the red cross at that spot on the screen (pixels) and he points at it
				_aim_at(Vector2(float(bits[1]), float(bits[2])))
			"sprint":
				_actor.sprinting = bits[1] == "1"
			"face":         # face:front, face:side, face:back, face:left (side-on, mirrored)
				_actor.face_way("side" if bits[1] == "left" else bits[1], bits[1] == "left")
			"wear":         # wear:hat:#cc2222 ... ; wear: alone puts his own clothes back
				if bits.size() < 3:
					_wear = {}
				else:
					_wear[bits[1]] = Color(bits[2])
				_actor.set_outfit(_wear)
			"arm":          # arm:TRE:ak or arm:TRE:ak:aim: give someone else here a weapon
				for member: Dictionary in _cast.get(_place, []):
					if String(member["actor"].name).to_lower() == bits[1].to_lower():
						member["actor"].weapon = "" if bits[2] == "none" else bits[2]
						member["actor"].aiming = bits.size() > 3
			"day":          # day:n: make it day n (0 is the first), and dress everyone for it
				_day = int(bits[1])
				_dress_for_day()
			"expr":         # expr:laugh (the lead) or expr:CHUY:calm (someone here), set as the game sets it
				var face_of: Node3D = _actor
				for member: Dictionary in _cast.get(_place, []):
					if bits.size() > 2 and String(member["actor"].name).to_lower() == bits[1].to_lower():
						face_of = member["actor"]
				if face_of.face:
					face_of.face.hold = false
					face_of.face.set_expression(bits[bits.size() - 1])
					print("[shot] expr: %s on %s" % [bits[bits.size() - 1], face_of.name])
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
	_fade.color.a = 0.0
	if _mode == "choose":
		pass                        # its own camera
	elif _performing:
		_perform_cam(0.0)
	else:
		_change_room(_building.room_at_pos(_actor.position, _room), true)
		if _close:
			_frame_close()
		elif _cam_name == "follow":
			_follow(0.0, true)
	_show_doors()
	if _shot_eye.size() == 6:
		_camera.fov = 50.0
		_camera.look_at_from_position(Vector3(_shot_eye[0], _shot_eye[1], _shot_eye[2]), Vector3(_shot_eye[3], _shot_eye[4], _shot_eye[5]))
		_face_cards()
	_find_nearest()
	if _shot_strip != "":           # run_strip.gd saves its own pictures
		_tag.visible = false
		_hint.visible = false
		await RunStrip.shoot(self, _camera, _shot_strip, _shot_path, _outfit_of(_look))
		get_tree().quit()
		return
	if _shot_lineup != "":
		_lineup(_shot_lineup)
	print("[shot] %s: in the %s at %.2f, %.2f; nearest: %s; window at %s" % [_place, _building.rooms[_room]["name"], _actor.position.x, _actor.position.z, _nearest.use_name() if _nearest else "-", DisplayServer.window_get_position()])
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save_frame(_shot_path)
	get_tree().quit()
