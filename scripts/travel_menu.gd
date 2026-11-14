extends CanvasLayer
## The travel list: the places he can go, in a box in the middle of the screen.
## Give it the places with `set_places` (each a Dictionary: "id", "name", "note",
## and "built": false for a place that is listed but cannot be picked yet).
## The row under the mouse turns yellow; click it or press its number. M or Esc
## closes the list without going anywhere. `picked` says which place was chosen.

signal picked(id: String)

const FONT := preload("res://assets/fonts/Bungee-Regular.ttf")
const PAPER := Color("#f6f1e3")
const TICKET := Color("#f2d24a")
const FAINT := Color(0.96, 0.94, 0.89, 0.34)
const SHADE := Color(14 / 255.0, 20 / 255.0, 40 / 255.0, 0.92)

var _places: Array = []
var _here := ""                # the id of the place he is in now
var _rows: VBoxContainer
var _names: Array = []         # the name label of each row


func _init() -> void:
	layer = 10
	var dim := ColorRect.new()                    # darkens the game behind, and takes clicks that miss the box
	dim.color = Color(0.02, 0.02, 0.05, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_miss)
	add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	var box := StyleBoxFlat.new()
	box.bg_color = SHADE
	box.set_corner_radius_all(16)
	box.set_border_width_all(4)
	box.border_color = Color("#14203f")
	box.content_margin_left = 40.0
	box.content_margin_right = 40.0
	box.content_margin_top = 26.0
	box.content_margin_bottom = 24.0
	panel.add_theme_stylebox_override("panel", box)
	centre.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	var title := _label(36, TICKET)
	title.text = "TRAVEL"
	column.add_child(title)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 12)
	column.add_child(_rows)
	var foot := _label(18, FAINT)
	foot.text = "M OR ESC   CLOSE"
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(foot)
	visible = false


func set_places(places: Array) -> void:
	_places = places


func is_open() -> bool:
	return visible


func open(here := "") -> void:
	_here = here
	_names = []
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for i in _places.size():
		var place: Dictionary = _places[i]
		var can_go: bool = place.get("built", true)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 24)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		var label := _label(28, PAPER if can_go else FAINT)
		label.text = "%d   %s" % [i + 1, place["name"]]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var note := _label(18, TICKET if place["id"] == _here else FAINT)
		note.text = "YOU ARE HERE" if place["id"] == _here else String(place.get("note", ""))
		note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(note)
		if can_go:
			row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			row.mouse_entered.connect(hover.bind(i))
			row.mouse_exited.connect(hover.bind(-1))
			row.gui_input.connect(_on_row_input.bind(i))
		_rows.add_child(row)
		_names.append(label)
	visible = true


func close() -> void:
	visible = false


## Colour row i as the one under the mouse (-1: none).
func hover(i: int) -> void:
	for n in _names.size():
		if _places[n].get("built", true):
			(_names[n] as Label).add_theme_color_override("font_color", TICKET if n == i else PAPER)


## Go to place i, if it can be gone to.
func pick(i: int) -> void:
	if not visible or i < 0 or i >= _places.size() or not _places[i].get("built", true):
		return
	visible = false
	picked.emit(String(_places[i]["id"]))


func _on_row_input(event: InputEvent, i: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		pick(i)


func _on_miss(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		close()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.pressed or event.echo:
		return
	var key: int = event.physical_keycode
	get_viewport().set_input_as_handled()        # while the list is up, no key reaches the game
	if key in [KEY_M, KEY_ESCAPE]:
		close()
	elif key >= KEY_1 and key <= KEY_9:
		pick(key - KEY_1)


func _label(size: int, colour: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	return label
