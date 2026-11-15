extends CanvasLayer
## The plan board for a music video: one row for each thing that can be paid
## for (assets/data/video.json's "rows": where, who comes, the bling, the cars,
## the cash to throw, the smoke), each choice a paper card with its price. Up /
## Down (W / S) picks the row, Left / Right (A / D) the card in it; a click
## picks a card too. Below: his cash, the total, the production it adds up to,
## and SHOOT IT (Enter, or a click), which can only be pressed while he can pay.
## Esc puts the board away and nothing is spent.
##
##   board.open(data, cash, title)      shoot(picks) / cancelled

signal shoot(picks: Dictionary)
signal cancelled

const Score := preload("res://scripts/video_score.gd")
const FONT := preload("res://assets/fonts/Bungee-Regular.ttf")
const PAPER := Color("#f6f1e3")
const TICKET := Color("#f2d24a")
const INK := Color("#1c1a22")
const FAINT := Color(0.96, 0.94, 0.89, 0.42)
const SHADE := Color(14 / 255.0, 20 / 255.0, 40 / 255.0, 0.94)
const SHORT := Color("#e2483a")

var row := 0                  # the row being picked in
var picks := {}               # row id: the number of the card picked in it

var _data := {}
var _words := {}
var _cash := 0
var _rows_box: VBoxContainer
var _cards: Array = []        # for each row, its cards (PanelContainers)
var _labels: Array = []       # for each row, its name
var _title: Label
var _cash_label: Label
var _total: Label
var _meter: ColorRect
var _meter_back: ColorRect
var _meter_value: Label
var _meter_name: Label
var _go: Label
var _go_box: PanelContainer
var _keys: Label
var _tip: Label
var _hover := Vector2i(-1, -1)


func _init() -> void:
	layer = 12
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1480, 0)
	var box := StyleBoxFlat.new()
	box.bg_color = SHADE
	box.set_corner_radius_all(16)
	box.set_border_width_all(4)
	box.border_color = Color("#14203f")
	box.content_margin_left = 34.0
	box.content_margin_right = 34.0
	box.content_margin_top = 22.0
	box.content_margin_bottom = 22.0
	panel.add_theme_stylebox_override("panel", box)
	centre.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)

	var head := HBoxContainer.new()
	column.add_child(head)
	_title = _label(38, TICKET)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_cash_label = _label(30, PAPER)
	_cash_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_cash_label)

	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 10)
	column.add_child(_rows_box)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 26)
	column.add_child(foot)
	_total = _label(30, PAPER)
	_total.custom_minimum_size = Vector2(330, 0)
	_total.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_total)
	var meter := VBoxContainer.new()
	meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meter.add_theme_constant_override("separation", 4)
	foot.add_child(meter)
	var meter_head := HBoxContainer.new()
	meter.add_child(meter_head)
	_meter_name = _label(18, FAINT)
	_meter_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meter_head.add_child(_meter_name)
	_meter_value = _label(18, PAPER)
	meter_head.add_child(_meter_value)
	_meter_back = ColorRect.new()
	_meter_back.color = Color(1, 1, 1, 0.12)
	_meter_back.custom_minimum_size = Vector2(0, 22)
	meter.add_child(_meter_back)
	_meter = ColorRect.new()
	_meter.color = TICKET
	_meter_back.add_child(_meter)
	_go_box = PanelContainer.new()
	_go_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_go_box.gui_input.connect(_on_go_input)
	foot.add_child(_go_box)
	_go = _label(30, INK)
	_go.add_theme_constant_override("outline_size", 0)
	_go_box.add_child(_go)

	var bottom := HBoxContainer.new()
	column.add_child(bottom)
	_tip = _label(17, TICKET)
	_tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_tip)
	_keys = _label(17, FAINT)
	bottom.add_child(_keys)


func is_open() -> bool:
	return visible


## Put the board up with the rows of `data` and nothing picked but the first
## (free) card of each row. `cash` is what he has.
func open(data: Dictionary, cash: int, title: String) -> void:
	_data = data
	_words = data.get("words", {})
	_cash = cash
	row = 0
	picks = {}
	for r: Dictionary in data["rows"]:
		picks[r["id"]] = 0
	_title.text = "%s   %s" % [_words.get("board", "SHOOT A VIDEO"), title]
	_tip.text = String(_words.get("board_tip", ""))
	_keys.text = String(_words.get("board_keys", ""))
	_meter_name.text = String(_words.get("production", "PRODUCTION"))
	_build_rows()
	visible = true
	_refresh()


func close() -> void:
	visible = false


## Pick card `choice` in the row with id `row_id` (a --do step and the mouse use this too).
func pick(row_id: String, choice: int) -> void:
	for i in _data["rows"].size():
		var r: Dictionary = _data["rows"][i]
		if r["id"] == row_id:
			picks[row_id] = clampi(choice, 0, r["choices"].size() - 1)
			row = i
	_refresh()


## Pick by the choice's id: pick_named("location", "court"). False if there is none.
func pick_named(row_id: String, choice_id: String) -> bool:
	for r: Dictionary in _data["rows"]:
		if r["id"] != row_id:
			continue
		for i in r["choices"].size():
			if String(r["choices"][i]["id"]) == choice_id:
				pick(row_id, i)
				return true
	return false


func total() -> int:
	return Score.price(_data["rows"], picks)


func can_shoot() -> bool:
	return total() <= _cash


## SHOOT IT: only while he can pay for it all.
func press_shoot() -> void:
	if not visible or not can_shoot():
		return
	visible = false
	shoot.emit(picks.duplicate())


func cancel() -> void:
	if not visible:
		return
	visible = false
	cancelled.emit()


func _build_rows() -> void:
	for child in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()
	_cards = []
	_labels = []
	for i in _data["rows"].size():
		var r: Dictionary = _data["rows"][i]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		_rows_box.add_child(line)
		var label := _label(22, PAPER)
		label.text = String(r["label"])
		label.custom_minimum_size = Vector2(196, 0)
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_child(label)
		_labels.append(label)
		var cards: Array = []
		var choices: Array = r["choices"]
		var wide := (1480.0 - 68.0 - 196.0 - 12.0 * choices.size()) / maxf(6.0, float(choices.size()))
		for k in choices.size():
			var card := _card(choices[k], wide, i, k)
			line.add_child(card)
			cards.append(card)
		_cards.append(cards)


## One choice: its name, a dry note, its price, on a paper card.
func _card(choice: Dictionary, wide: float, i: int, k: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(wide, 96)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.mouse_entered.connect(func() -> void:
		_hover = Vector2i(i, k)
		_refresh())
	card.mouse_exited.connect(func() -> void:
		if _hover == Vector2i(i, k):
			_hover = Vector2i(-1, -1)
		_refresh())
	card.gui_input.connect(_on_card_input.bind(i, k))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)
	var title := _ink(16)
	title.text = String(choice["name"])
	title.name = "Name"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title)
	var note := _ink(12)
	note.text = String(choice.get("note", ""))
	note.name = "Note"
	note.modulate.a = 0.7
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(note)
	var price := _ink(20)
	var cost := int(choice.get("price", 0))
	price.text = String(_words.get("free", "FREE")) if cost == 0 else _money(cost)
	price.name = "Price"
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(price)
	return card


func _refresh() -> void:
	if _data.is_empty():
		return
	for i in _cards.size():
		var r: Dictionary = _data["rows"][i]
		(_labels[i] as Label).add_theme_color_override("font_color", TICKET if i == row else PAPER)
		for k in _cards[i].size():
			var card: PanelContainer = _cards[i][k]
			var on: bool = int(picks[r["id"]]) == k
			var look := StyleBoxFlat.new()
			look.bg_color = TICKET if on else (PAPER if _hover != Vector2i(i, k) else PAPER.lerp(TICKET, 0.35))
			look.set_corner_radius_all(6)
			look.set_border_width_all(5 if on and i == row else 3)
			look.border_color = INK if on else Color(0.1, 0.1, 0.13)
			look.shadow_color = Color(0, 0, 0, 0.45)
			look.shadow_size = 4
			look.shadow_offset = Vector2(3, 4)
			look.content_margin_left = 12.0
			look.content_margin_right = 12.0
			look.content_margin_top = 8.0
			look.content_margin_bottom = 6.0
			card.add_theme_stylebox_override("panel", look)
			var cost := int(r["choices"][k].get("price", 0))
			var price: Label = card.get_child(0).get_node("Price")
			price.add_theme_color_override("font_color", SHORT if cost > _cash else INK)
	var sum := total()
	_cash_label.text = "%s  %s" % [_words.get("cash", "CASH"), _money(_cash)]
	_total.text = "%s  %s" % [_words.get("total", "TOTAL"), _money(sum)]
	var prod := Score.production(_data["rows"], picks)
	_meter_value.text = "%d" % prod
	var go := StyleBoxFlat.new()
	go.set_corner_radius_all(8)
	go.set_border_width_all(4)
	go.border_color = INK
	go.content_margin_left = 22.0
	go.content_margin_right = 22.0
	go.content_margin_top = 8.0
	go.content_margin_bottom = 8.0
	if can_shoot():
		go.bg_color = TICKET
		_go.text = "ENTER  " + String(_words.get("shoot", "SHOOT IT"))
		_go.add_theme_color_override("font_color", INK)
		_go_box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	else:
		go.bg_color = Color(0.3, 0.3, 0.34)
		_go.text = String(_words.get("short", "${n} SHORT")).replace("${n}", _money(sum - _cash))
		_go.add_theme_color_override("font_color", SHORT.lightened(0.3))
		_go_box.mouse_default_cursor_shape = Control.CURSOR_ARROW
	_go_box.add_theme_stylebox_override("panel", go)


func _process(_delta: float) -> void:
	if visible and _meter_back.size.x > 0.0:      # the meter's width is known once the board is laid out
		_meter.size = Vector2(_meter_back.size.x * Score.production(_data["rows"], picks) / 100.0, 22)


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()        # while the board is up, no key reaches the game
	var rows: Array = _data["rows"]
	match event.physical_keycode:
		KEY_ESCAPE:
			cancel()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			press_shoot()
		KEY_UP, KEY_W:
			row = posmod(row - 1, rows.size())
			_refresh()
		KEY_DOWN, KEY_S:
			row = posmod(row + 1, rows.size())
			_refresh()
		KEY_LEFT, KEY_A, KEY_RIGHT, KEY_D:
			var step := -1 if event.physical_keycode in [KEY_LEFT, KEY_A] else 1
			var r: Dictionary = rows[row]
			picks[r["id"]] = posmod(int(picks[r["id"]]) + step, r["choices"].size())
			_refresh()


func _on_card_input(event: InputEvent, i: int, k: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		pick(String(_data["rows"][i]["id"]), k)


func _on_go_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		press_shoot()


static func _money(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return ("-$" if n < 0 else "$") + out


func _label(size: int, colour: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	return label


## Dark ink on a paper card.
func _ink(size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", INK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
