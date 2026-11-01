extends Control
## Modal, camera-stable text conversations; no world/mission writes outside choice hooks.
const C := preload("res://scripts/city/city_theme.gd")
const T := C.T
const State := preload("res://scripts/city/city_dialogue_state.gd")
signal closed
var state := State.new()
var speaker: Label
var line: Label
var replies: VBoxContainer
var card: PanelContainer

func _ready() -> void:
	name = "Conversation"
	theme = C.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = T.a(T.INK, 0.22)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card = T.panel(C.case_file())
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(card)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(scroll)
	var column := T.vbox(10)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	speaker = T.label("", T.ls(T.disp(22), 22, T.SIREN), HORIZONTAL_ALIGNMENT_LEFT, true)
	column.add_child(speaker)
	line = T.label("", T.ls(T.body(600), 26, T.INK), HORIZONTAL_ALIGNMENT_LEFT, true)
	column.add_child(line)
	replies = T.vbox(8)
	column.add_child(replies)
	column.add_child(T.label("E / Enter / Space  Continue    ↑ / ↓  Choose    Esc  Leave", T.ls(T.mono(), 14, T.INK), HORIZONTAL_ALIGNMENT_LEFT, true))
	state.changed.connect(_refresh)
	state.closed.connect(func(): hide(); closed.emit())
	resized.connect(_layout)
	_layout()
	hide()

func _layout() -> void:
	var width := minf(860, maxf(260, size.x - 40))
	card.position = Vector2((size.x - width) * 0.5, size.y * 0.52)
	card.size = Vector2(width, maxf(130, size.y * 0.48 - 24))

func open(data: Dictionary, conditions: Callable, hooks: Callable) -> bool:
	var opened := state.open(data, conditions, hooks)
	visible = opened
	return opened

func close() -> void:
	state.close()

func _refresh() -> void:
	var current := state.current()
	speaker.text = T.caps(str(current.get("speaker", "Neighbor")))
	line.text = str(current.get("text", ""))
	for child in replies.get_children():
		replies.remove_child(child)
		child.queue_free()
	var choices := state.choices()
	for index in choices.size():
		var button := Button.new()
		button.text = ("› " if index == state.selected else "  ") + str(choices[index].get("text", "Continue"))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func(): state.choose(index))
		replies.add_child(button)

func handle_input(event: InputEvent) -> bool:
	if not state.active:
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE: close()
			KEY_E, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: state.advance()
			KEY_UP, KEY_DOWN:
				var count := state.choices().size()
				if count > 0:
					state.selected = posmod(state.selected + (-1 if event.keycode == KEY_UP else 1), count)
					_refresh()
	# Mouse clicks must reach GUI buttons. Every keyboard/look event is captured here.
	return event is InputEventKey or event is InputEventMouseMotion
