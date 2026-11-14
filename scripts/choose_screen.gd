extends Node3D
## The start of a new game: who does he listen to? A black screen, the lead in
## the middle seen from the chest up, a little angel at one shoulder and a
## little devil at the other.
##
## Until one is picked his eyes dart from one to the other and the camera
## drifts a little from side to side; START is greyed out. Click the angel or
## the devil (or press Left / Right): its outline glows (the angel's gold and
## white, the devil's red), the other one dims, his eyes stay on the one he
## picked (he still blinks) and START can be pressed. Clicking the same one
## again lets go of it. Esc goes back.
##
## The two little figures are never still. Both blink, lift their brows and
## stretch and squash a little as they breathe. The angel hovers, beats his
## wings and raises and lowers his praying hands; the devil flicks his tail,
## lifts his pitchfork and sets it down, and bounces on his heels. Each is one
## drawing: shaders/paper_glow.gdshader moves the parts, and build_choice.py
## says where they are (assets/ui/<name>.json and <name>_parts.png).
##
##   var choose: Node3D = ChooseScreen.new()
##   add_child(choose)
##   choose.build("res://assets/characters/e")
##   choose.open()          # and close() when done
##   choose.started.connect(func(side): ...)      # "angel" or "devil"
##
## It stands far above the rest of the world with its own camera and its own
## black backdrop, so nothing else is in the picture.

signal started(side: String)
signal cancelled

const PaperActor := preload("res://scripts/paper_actor.gd")
const GLOW := preload("res://shaders/paper_glow.gdshader")
const FONT := preload("res://assets/fonts/Bungee-Regular.ttf")
const PAPER := Color("#f6f1e3")
const TICKET := Color("#f2d24a")
const FAINT := Color(0.96, 0.94, 0.89, 0.34)

const SIDES := ["angel", "devil"]
const FIGURE := 0.4                  # how tall each little figure stands, metres
const MARGIN := 0.16                  # the clear margin round the figure in its picture, as a fraction of the figure's height (build_choice.py)
const SPOTS := {"angel": Vector3(-0.39, 0.7, 0.08), "devil": Vector3(0.39, 0.7, 0.08)}        # where their feet are: on each shoulder, by his ear
const LOOKS := {"angel": -1.0, "devil": 1.0}                                                  # which way he looks at each, on screen
const GLOWS := {
	"angel": [Color(1.0, 0.84, 0.3), Color(1.0, 1.0, 0.92)],
	"devil": [Color(1.0, 0.1, 0.06), Color(1.0, 0.5, 0.35)],
}
const MOODS := {"": "nervous", "angel": "happy", "devil": "smug"}
const NAMES := {"": "WHO DO YOU LISTEN TO?", "angel": "THE ANGEL", "devil": "THE DEVIL"}
const TINTS := {"": FAINT, "angel": Color(1.0, 0.92, 0.6), "devil": Color(1.0, 0.35, 0.28)}
const EYE := Vector3(0.0, 0.96, 2.75)        # the camera, and what it looks at: low, so he stands in the top of the picture, clear of START
const AIM := Vector3(0.0, 0.86, 0.0)
const BLINK := 0.16                   # seconds a blink of theirs takes, shut and open again

var chosen := ""                      # "", "angel" or "devil"

var _lead: Node3D
var _cards := {}                      # side: MeshInstance3D
var _mats := {}                       # side: ShaderMaterial
var _camera: Camera3D
var _ui: CanvasLayer
var _start: Button
var _caption: Label
var _time := 0.0
var _pan := 1.0                       # how much the camera drifts: 1 while nobody is picked, easing to 0 once someone is
var _eyes_on := "angel"               # who his eyes are on while he cannot decide
var _eyes_in := 0.8                   # seconds until they dart across
var _hover := ""
var _size := {}                       # side: how big it is drawn (1, a little more under the mouse, more when picked)
var _blinks := {}                     # side: {"in": seconds until the next blink, "left": seconds of this one still to run}
var _rng := RandomNumberGenerator.new()


func build(rig_dir: String) -> void:
	Kit.box(self, Vector3(60.0, 40.0, 0.1), Vector3(0, 1, -4), Color.BLACK)      # the black behind everything
	_lead = PaperActor.new()
	_lead.name = "Lead"
	add_child(_lead)
	_lead.set_rig(rig_dir)
	for side: String in SIDES:
		var art: Texture2D = load("res://assets/ui/%s.png" % side)
		var px := Vector2(art.get_size())
		var tall := FIGURE * (1.0 + 2.0 * MARGIN)
		var quad := QuadMesh.new()
		quad.size = Vector2(tall * px.x / px.y, tall)
		quad.center_offset = Vector3(0, tall * 0.5 - FIGURE * MARGIN, 0)      # the node's origin is at the figure's feet
		var mat := ShaderMaterial.new()
		mat.shader = GLOW
		mat.set_shader_parameter("art", art)
		mat.set_shader_parameter("aspect", px.x / px.y)
		mat.set_shader_parameter("glow_colour", GLOWS[side][0])
		mat.set_shader_parameter("core_colour", GLOWS[side][1])
		mat.set_shader_parameter("glow", 0.0)
		mat.set_shader_parameter("dim", 1.0)
		mat.set_shader_parameter("rim", 0.45)
		# What can move, and where it is on the picture.
		var map = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/%s.json" % side))
		if typeof(map) == TYPE_DICTIONARY:
			mat.set_shader_parameter("parts", load("res://assets/ui/%s_parts.png" % side))
			mat.set_shader_parameter("has_parts", true)
			for key: String in map["parts"]:
				var part: Dictionary = map["parts"][key]
				mat.set_shader_parameter("pivot_" + key, Vector3(part["pivot"][0], part["pivot"][1], part["reach"]))
			for i in 2:
				var eye: Array = map["eyes"][i]
				var brow: Array = map["brows"][i]
				mat.set_shader_parameter(["eye_l", "eye_r"][i], Vector4(eye[0], eye[1], eye[2], eye[3]))
				mat.set_shader_parameter(["brow_l", "brow_r"][i], Vector4(brow[0], brow[1], brow[2], brow[3]))
			mat.set_shader_parameter("eye_top", Vector2(map["eyes"][0][4], map["eyes"][1][4]))
			mat.set_shader_parameter("skin", Color(map["skin"][0], map["skin"][1], map["skin"][2]))
		else:
			push_warning("Could not read assets/ui/%s.json: the %s will not move" % [side, side])
		_size[side] = 1.0
		_blinks[side] = {"in": 1.0 + SIDES.find(side) * 0.9, "left": 0.0}
		var card := MeshInstance3D.new()
		card.name = side.capitalize()
		card.mesh = quad
		card.material_override = mat
		card.position = SPOTS[side]
		add_child(card)
		_cards[side] = card
		_mats[side] = mat
	_camera = Camera3D.new()
	_camera.fov = 30.0
	add_child(_camera)

	_ui = CanvasLayer.new()
	_ui.layer = 12
	add_child(_ui)
	# He fades into the black below the chest, so the words and the button sit on plain black.
	var fall := Gradient.new()
	fall.set_color(0, Color(0, 0, 0, 0))
	fall.set_color(1, Color(0, 0, 0, 1))
	var shade_art := GradientTexture2D.new()
	shade_art.gradient = fall
	shade_art.fill_from = Vector2(0, 0)
	shade_art.fill_to = Vector2(0, 0.5)
	shade_art.width = 8
	shade_art.height = 64
	var shade := TextureRect.new()
	shade.texture = shade_art
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.anchor_left = 0.0
	shade.anchor_right = 1.0
	shade.anchor_top = 0.6
	shade.anchor_bottom = 1.0
	_ui.add_child(shade)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	column.offset_bottom = -44.0
	column.add_theme_constant_override("separation", 14)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(column)
	_caption = Label.new()
	_caption.add_theme_font_override("font", FONT)
	_caption.add_theme_font_size_override("font_size", 26)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_caption)
	_start = Button.new()
	_start.text = "START"
	_start.custom_minimum_size = Vector2(300, 64)
	_start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_start.focus_mode = Control.FOCUS_NONE
	_start.add_theme_font_override("font", FONT)
	_start.add_theme_font_size_override("font_size", 32)
	_start.add_theme_color_override("font_color", Color("#14203f"))
	_start.add_theme_color_override("font_hover_color", Color("#14203f"))
	_start.add_theme_color_override("font_pressed_color", Color("#14203f"))
	_start.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.52))
	_start.add_theme_stylebox_override("normal", _box(TICKET))
	_start.add_theme_stylebox_override("hover", _box(TICKET.lightened(0.25)))
	_start.add_theme_stylebox_override("pressed", _box(TICKET.darkened(0.15)))
	_start.add_theme_stylebox_override("disabled", _box(Color(0.2, 0.2, 0.22)))
	_start.pressed.connect(start)
	column.add_child(_start)
	var foot := Label.new()
	foot.text = "CLICK ONE, OR LEFT / RIGHT     ENTER  START     ESC  BACK"
	foot.add_theme_font_override("font", FONT)
	foot.add_theme_font_size_override("font_size", 14)
	foot.add_theme_color_override("font_color", FAINT)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(foot)
	close()


func _box(colour: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(12)
	return box


func open() -> void:
	visible = true
	_ui.visible = true
	_time = 0.0
	_pan = 1.0
	_hover = ""
	choose("")
	_camera.current = true
	set_process(true)
	set_process_unhandled_input(true)
	_process(0.0)


func close() -> void:
	visible = false
	_ui.visible = false
	set_process(false)
	set_process_unhandled_input(false)


## Pick a side ("angel" or "devil"), or "" to let go.
func choose(side: String) -> void:
	chosen = side
	_start.disabled = side == ""
	_start.mouse_default_cursor_shape = Control.CURSOR_ARROW if side == "" else Control.CURSOR_POINTING_HAND
	_caption.text = NAMES[side]
	_caption.add_theme_color_override("font_color", TINTS[side])
	if _lead.face:
		_lead.face.set_expression(MOODS[side])
		_lead.face.look(LOOKS.get(side, LOOKS[_eyes_on]))
	_eyes_in = 0.5


## Begin the game with the side picked (nothing happens while none is).
func start() -> void:
	if chosen != "":
		started.emit(chosen)


func _process(delta: float) -> void:
	_time += delta
	_lead.walk(Vector2.ZERO, Vector2.ZERO, delta)
	# Undecided: his eyes go from one to the other, a little unevenly.
	if chosen == "" and _lead.face:
		_eyes_in -= delta
		if _eyes_in <= 0.0:
			_eyes_in = _rng.randf_range(0.55, 1.2)
			_eyes_on = "devil" if _eyes_on == "angel" else "angel"
			_lead.face.look(LOOKS[_eyes_on])
	# The camera drifts while he is undecided and settles once he is not.
	_pan = move_toward(_pan, 1.0 if chosen == "" else 0.0, delta * 1.5)
	var drift := Vector3(0.2 * sin(_time * 0.55), 0.03 * sin(_time * 0.38), 0.0) * smoothstep(0.0, 1.0, _pan)
	_camera.look_at_from_position(to_global(EYE + drift), to_global(AIM + drift * 0.25))
	# The two of them. The one picked glows and grows a little, the other
	# fades back; picked or not, they keep moving.
	var k := 1.0 - exp(-10.0 * delta) if delta > 0.0 else 1.0
	var t := _time
	for side: String in SIDES:
		var card: MeshInstance3D = _cards[side]
		var mat: ShaderMaterial = _mats[side]
		var picked := chosen == side
		var lift := 0.0                 # how far off his perch, metres
		var stretch := 0.0              # taller and thinner by this much (negative: squashed)
		var brows := Vector2.ZERO       # how far up each brow is, of the picture's height
		if side == "angel":
			# He hovers, breathing slowly: the wings beat, the praying hands rise and sink.
			var beat := sin(t * 5.2)
			mat.set_shader_parameter("move_r", Vector3(0, 0, 0.16 * beat))
			mat.set_shader_parameter("move_g", Vector3(0, 0, -0.16 * beat))
			mat.set_shader_parameter("move_b", Vector3(0, -0.012 * (0.5 + 0.5 * sin(t * 1.3)), 0))
			lift = 0.02 * sin(t * 1.7)
			stretch = 0.022 * sin(t * 1.7 + 1.1)
			brows = Vector2.ONE * (0.0015 + 0.0045 * sin(t * 0.9))
		else:
			# He cannot keep still: the tail flicks, the pitchfork goes up and comes down, he bounces on his heels.
			mat.set_shader_parameter("move_r", Vector3(0, 0, 0.07 * sin(t * 2.3) + 0.03 * sin(t * 5.1)))
			mat.set_shader_parameter("move_g", Vector3(0, -0.026 * pow(0.5 - 0.5 * cos(t * 1.5), 2.0), 0))
			lift = 0.012 * absf(sin(t * 1.3))
			stretch = 0.03 * sin(t * 2.6)
			brows = Vector2(0.002 * sin(t * 1.1), 0.0015 + 0.0045 * sin(t * 1.9))
		mat.set_shader_parameter("brow_lift", brows)
		var size := 1.14 if picked else (1.05 if _hover == side else 1.0)
		_size[side] = lerpf(_size[side], size, k)
		card.position = SPOTS[side] + Vector3(0, lift, 0)
		card.scale = Vector3(1.0 - stretch * 0.6, 1.0 + stretch, 1.0) * float(_size[side])      # about his feet
		# A blink now and then: shut and open again.
		var eyes: Dictionary = _blinks[side]
		eyes["in"] -= delta
		if eyes["in"] <= 0.0:
			eyes["in"] = _rng.randf_range(1.8, 4.6)
			eyes["left"] = BLINK
		eyes["left"] = maxf(eyes["left"] - delta, 0.0)
		mat.set_shader_parameter("blink", eyes.get("hold", clampf(1.7 * sin(PI * eyes["left"] / BLINK), 0.0, 1.0)))      # "hold": for a still picture
		var pulse := 0.85 + 0.15 * sin(_time * 3.2)
		var glow_now: float = mat.get_shader_parameter("glow")
		mat.set_shader_parameter("glow", lerpf(glow_now, pulse if picked else 0.0, k))
		var dim_now: float = mat.get_shader_parameter("dim")
		mat.set_shader_parameter("dim", lerpf(dim_now, 0.42 if chosen != "" and not picked else 1.0, k))
	var over := _side_at(get_viewport().get_mouse_position())
	if over != _hover:
		_hover = over
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if over != "" else Input.CURSOR_ARROW)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var side := _side_at(event.position)
		if side != "":
			get_viewport().set_input_as_handled()
			choose("" if side == chosen else side)
	elif event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		match event.physical_keycode:
			KEY_LEFT, KEY_A:
				choose("angel")
			KEY_RIGHT, KEY_D:
				choose("devil")
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				start()
			KEY_ESCAPE:
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
				cancelled.emit()


## Which of the two is under this point of the screen ("" for neither).
func _side_at(screen: Vector2) -> String:
	for side: String in SIDES:
		var card: MeshInstance3D = _cards[side]
		var half := (card.mesh as QuadMesh).size.x * 0.32 * card.scale.x       # the figure, not its clear margin
		var foot := card.global_position
		var a := _camera.unproject_position(foot + Vector3(-half, FIGURE * card.scale.y, 0))
		var b := _camera.unproject_position(foot + Vector3(half, 0, 0))
		if Rect2(a, b - a).abs().has_point(screen):
			return side
	return ""
