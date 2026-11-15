extends CanvasLayer
## The travel list: the places he can go, in a box in the middle of the screen
## (one day a map). Give it the places with `set_places` (each a Dictionary:
## "id", "name", "note", and "built": false for a place that is listed but
## cannot be picked yet).
##
## However many places there are, the box stays on a 1280 x 720 screen: up to
## ONE_COLUMN rows in one column, more in two side by side, and past TALL rows a
## column the two scroll together (the mouse wheel, or the arrows).
##
## Pick a place by clicking its row, by its key (1 to 9, 0, then the letters but
## E and M: KEYS, thirty-four of them; a row past those has none), or with the
## arrows and Enter: the first arrow lights the row of the place he is in, the
## next move the light (Up and Down along the list, Left and Right across the
## columns). The row under the mouse or the light turns yellow. M or Esc closes
## the list without going anywhere. `picked` says which place was chosen.

signal picked(id: String)

const FONT := preload("res://assets/fonts/Bungee-Regular.ttf")
const KEYS := "1234567890ABCDFGHIJKLNOPQRSTUVWXYZ"      # the key for each row, top to bottom and then the next column (M and Esc close the list; E is left alone)
const PAPER := Color("#f6f1e3")
const TICKET := Color("#f2d24a")
const FAINT := Color(0.96, 0.94, 0.89, 0.5)
const SHADE := Color(14 / 255.0, 20 / 255.0, 40 / 255.0, 0.98)
const BAND := Color(0.95, 0.82, 0.29, 0.13)      # behind the lit row
const ONE_COLUMN := 8          # this many places or fewer: one column
const TALL := 15               # rows a column shows; more than that and the columns scroll
const ROW_H := 36.0            # each row's height on the 1600 x 900 canvas (the window is that, scaled)
const ROW_GAP := 4.0
const COL_W := 600.0
const COL_GAP := 40.0

var _places: Array = []
var _here := ""                # the id of the place he is in now
var _scroll: ScrollContainer
var _columns: HBoxContainer
var _count: Label
var _rows: Array = []          # each row's band (the row in it), in list order
var _plain: StyleBoxFlat       # a band: clear, or lit with a yellow edge
var _lit_band: StyleBoxFlat
var _names: Array = []         # the name label of each row
var _keys: Array = []          # the key label of each row
var _lit := -1                 # the row lit by the mouse or the arrows
var _per_column := 1


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
	var box := StyleBoxFlat.new()
	box.bg_color = SHADE
	box.set_corner_radius_all(16)
	box.set_border_width_all(4)
	box.border_color = Color("#14203f")
	box.content_margin_left = 36.0
	box.content_margin_right = 36.0
	box.content_margin_top = 22.0
	box.content_margin_bottom = 20.0
	panel.add_theme_stylebox_override("panel", box)
	centre.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	var title := _label(36, TICKET)
	title.text = "TRAVEL"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_count = _label(16, FAINT)
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_count)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.name = "Rows"
	column.add_child(_scroll)
	_columns = HBoxContainer.new()
	_columns.add_theme_constant_override("separation", int(COL_GAP))
	_scroll.add_child(_columns)
	var foot := _label(16, FAINT)
	foot.text = "CLICK, A KEY, OR THE ARROWS AND ENTER     M OR ESC  CLOSE"
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(foot)
	_plain = StyleBoxFlat.new()                      # no margins: a band is its row's size (the scroll's sums count on it)
	_plain.bg_color = Color(0, 0, 0, 0)
	_plain.set_corner_radius_all(6)
	_plain.set_content_margin_all(0.0)
	_lit_band = _plain.duplicate()
	_lit_band.bg_color = BAND
	_lit_band.border_width_left = 4
	_lit_band.border_color = TICKET
	visible = false


func set_places(places: Array) -> void:
	_places = places


func is_open() -> bool:
	return visible


func open(here := "") -> void:
	_here = here
	_rows = []
	_names = []
	_keys = []
	_lit = -1
	for child in _columns.get_children():
		_columns.remove_child(child)
		child.queue_free()
	var n := _places.size()
	var cols := 1 if n <= ONE_COLUMN else 2
	_per_column = maxi(ceili(float(n) / cols), 1)
	for c in cols:
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", int(ROW_GAP))
		_columns.add_child(list)
		for i in range(c * _per_column, mini(n, (c + 1) * _per_column)):
			list.add_child(_row(i))
	var shown := mini(_per_column, TALL)
	var bar := 18.0 if _per_column > TALL else 0.0          # room for the scroll bar
	_scroll.custom_minimum_size = Vector2(cols * COL_W + (cols - 1) * COL_GAP + bar, shown * (ROW_H + ROW_GAP) - ROW_GAP)
	_scroll.scroll_vertical = 0
	_count.text = "%d PLACES" % n
	visible = true


## One place's row: its key, its name, and its note (or YOU ARE HERE).
func _row(i: int) -> Control:
	var place: Dictionary = _places[i]
	var can_go: bool = place.get("built", true)
	var band := PanelContainer.new()
	band.add_theme_stylebox_override("panel", _plain)
	band.mouse_filter = Control.MOUSE_FILTER_PASS         # a click is the row's; the wheel goes on to the scroll
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(COL_W, ROW_H)
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(row)
	var key := _label(22, TICKET if can_go else FAINT)
	key.text = KEYS[i] if i < KEYS.length() else ""
	key.custom_minimum_size = Vector2(34, 0)
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(key)
	var label := _label(22, PAPER if can_go else FAINT)
	label.text = String(place["name"])
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(label)
	var here: bool = place["id"] == _here
	var note := _label(15, TICKET if here else FAINT)
	note.text = "YOU ARE HERE" if here else String(place.get("note", ""))
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	note.custom_minimum_size = Vector2(0, 0)
	row.add_child(note)
	if can_go:
		band.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		band.mouse_entered.connect(hover.bind(i))
		band.mouse_exited.connect(func() -> void:
			if _lit == i:
				hover(-1))
		band.gui_input.connect(_on_row_input.bind(i))
	_rows.append(band)
	_names.append(label)
	_keys.append(key)
	return band


func close() -> void:
	visible = false


## Light row i, as the one under the mouse or the arrows (-1: none): its name yellow, a band behind it. And
## scroll it into sight.
func hover(i: int) -> void:
	_lit = i
	for n in _names.size():
		if _places[n].get("built", true):
			(_names[n] as Label).add_theme_color_override("font_color", TICKET if n == i else PAPER)
			(_rows[n] as PanelContainer).add_theme_stylebox_override("panel", _lit_band if n == i else _plain)
	if i >= 0 and i < _rows.size() and visible:
		_scroll.ensure_control_visible(_rows[i])


## Go to place i, if it can be gone to.
func pick(i: int) -> void:
	if not visible or i < 0 or i >= _places.size() or not _places[i].get("built", true):
		return
	visible = false
	picked.emit(String(_places[i]["id"]))


## The arrows: the first lights the place he is in; then Up and Down step along the list, Left and Right jump a column.
func _step(by: int) -> void:
	var n := _places.size()
	if n == 0:
		return
	if _lit < 0:
		var start := 0
		for i in n:
			if _places[i]["id"] == _here:
				start = i
		hover(start)
		return
	var to := _lit + by
	if absi(by) == 1:
		to = posmod(to, n)
	elif to < 0 or to >= n:
		to = clampi(to, 0, n - 1)
		if floori(float(to) / _per_column) == floori(float(_lit) / _per_column):      # no column that way
			return
	hover(to)


func _on_row_input(event: InputEvent, i: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		pick(i)


func _on_miss(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		close()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.pressed:
		return
	var key: int = event.physical_keycode
	get_viewport().set_input_as_handled()        # while the list is up, no key reaches the game
	if event.echo and not key in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		return                                   # a held arrow keeps stepping; nothing else repeats
	match key:
		KEY_M, KEY_ESCAPE:
			close()
		KEY_ENTER, KEY_KP_ENTER:
			pick(_lit)
		KEY_UP:
			_step(-1)
		KEY_DOWN:
			_step(1)
		KEY_LEFT:
			_step(-_per_column)
		KEY_RIGHT:
			_step(_per_column)
		_:
			var i := KEYS.find(OS.get_keycode_string(key))
			if i >= 0:
				pick(i)


func _label(size: int, colour: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	return label
