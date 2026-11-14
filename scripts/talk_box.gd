extends CanvasLayer
## The conversation box. It runs one conversation between the player and one
## other character from a table of nodes (see assets/data/talk_fry.json):
##
##   a node with "choices" lists things the player can say; each has "say",
##     the node to go to "next", and optionally the "face" he says it with;
##   any other node is one line: who says it ("speaker": "npc" or "player"),
##     the "line", optionally a "face", and the "next" node ("" ends the talk).
##
## Lines type out, and the speaker's mouth moves while they do. Choices turn
## yellow under the mouse; click one, or press its number. E, Space, Enter or a
## click (on the box or anywhere else) finishes a line that is still typing,
## then moves on. Esc ends the conversation there and then.

signal closed

const FONT := preload("res://assets/fonts/Bungee-Regular.ttf")   # Pen Lucy's display font; capitals only
const PAPER := Color("#f6f1e3")
const TICKET := Color("#f2d24a")                                  # Pen Lucy's yellow
const SHADE := Color(14 / 255.0, 20 / 255.0, 40 / 255.0, 0.88)
const TYPE_RATE := 42.0        # characters a second

var _nodes := {}
var _cast := {}                # "player" / "npc": the paper actor
var _panel: PanelContainer
var _name: Label
var _line: Label
var _choices: VBoxContainer
var _more: Label
var _options: Array = []       # the choices on show
var _typing := false
var _typed := 0.0
var _speaker: Node3D
var _next := ""


func _init() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 130.0
	_panel.offset_right = -130.0
	_panel.offset_top = -262.0
	_panel.offset_bottom = -34.0
	var box := StyleBoxFlat.new()
	box.bg_color = SHADE
	box.set_corner_radius_all(16)
	box.set_border_width_all(4)
	box.border_color = Color("#14203f")
	box.content_margin_left = 34.0
	box.content_margin_right = 34.0
	box.content_margin_top = 20.0
	box.content_margin_bottom = 20.0
	_panel.add_theme_stylebox_override("panel", box)
	_panel.gui_input.connect(_on_box_input)      # a click on the box or its text never reaches _unhandled_input
	add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_panel.add_child(column)
	_name = _label(30, TICKET)
	column.add_child(_name)
	_line = _label(27, PAPER)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_line)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 10)
	_choices.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_choices)
	_more = _label(20, TICKET)
	_more.text = "E"
	_more.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(_more)
	visible = false


func is_open() -> bool:
	return visible


func start(data: Dictionary, player: Node3D, npc: Node3D) -> void:
	_nodes = data["nodes"]
	_cast = {"player": player, "npc": npc}
	visible = true
	_go(data["start"])


## What the player can say right now (empty while a line is on show).
func options() -> Array:
	return _options


## Finish the line that is typing, or move on from a finished one.
func advance() -> void:
	if not visible or not _options.is_empty():
		return
	if _typing:
		_finish_typing()
	else:
		_go(_next)


## Say one of the choices on show.
func pick(i: int) -> void:
	if i < 0 or i >= _options.size():
		return
	var choice: Dictionary = _options[i]
	_say("player", choice["say"], choice.get("next", ""), choice.get("face", ""))


## Colour choice i as the one under the mouse (-1: none).
func hover(i: int) -> void:
	for n in _choices.get_child_count():
		(_choices.get_child(n) as Label).add_theme_color_override("font_color", TICKET if n == i else PAPER)


func _go(id: String) -> void:
	if id == "" or not _nodes.has(id):
		_close()
		return
	var node: Dictionary = _nodes[id]
	if node.has("choices"):
		_show_choices(node["choices"])
	else:
		_say(node.get("speaker", "npc"), node["line"], node.get("next", ""), node.get("face", ""))


func _say(who: String, text: String, next: String, face: String) -> void:
	_clear_choices()
	_speaker = _cast[who]
	_next = next
	_name.text = _speaker.display_name
	_name.visible = true
	_line.text = text
	_line.visible_characters = 0
	_line.visible = true
	_more.visible = false
	_typed = 0.0
	_typing = true
	if _speaker.face:
		if face != "":
			_speaker.face.set_expression(face)
		_speaker.face.talking = true


func _show_choices(list: Array) -> void:
	_clear_choices()
	_options = list
	_name.text = _cast["player"].display_name
	_line.visible = false
	_more.visible = false
	for i in list.size():
		var label := _label(26, PAPER)
		label.text = "%d   %s" % [i + 1, list[i]["say"]]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		label.mouse_entered.connect(hover.bind(i))
		label.mouse_exited.connect(hover.bind(-1))
		label.gui_input.connect(_on_choice_input.bind(i))
		_choices.add_child(label)
	_choices.visible = true


func _on_choice_input(event: InputEvent, i: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		pick(i)


func _on_box_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		advance()


func _clear_choices() -> void:
	_options = []
	_choices.visible = false
	for child in _choices.get_children():
		_choices.remove_child(child)
		child.queue_free()


func _finish_typing() -> void:
	_typing = false
	_line.visible_characters = -1
	_more.visible = true
	if _speaker and _speaker.face:
		_speaker.face.talking = false


func _close() -> void:
	_clear_choices()
	visible = false
	for who: String in _cast:
		var actor: Node3D = _cast[who]
		if actor.face:
			actor.face.talking = false
			actor.face.set_expression("neutral")
	closed.emit()


func _process(delta: float) -> void:
	if not _typing:
		return
	_typed += TYPE_RATE * delta
	_line.visible_characters = int(_typed)
	if _typed >= _line.text.length():
		_finish_typing()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode
		if key >= KEY_1 and key <= KEY_9 and not _options.is_empty():
			get_viewport().set_input_as_handled()
			pick(key - KEY_1)
		elif key in [KEY_E, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			get_viewport().set_input_as_handled()
			advance()
		elif key == KEY_ESCAPE:           # walk away from the conversation
			get_viewport().set_input_as_handled()
			_typing = false
			_close()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		advance()


func _label(size: int, colour: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	return label
