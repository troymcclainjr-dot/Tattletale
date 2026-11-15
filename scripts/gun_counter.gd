extends CanvasLayer
## The gun store's counter list (gun_shop.gd opens it with E at the counter): what he can buy, a row each, with
## the weapon's picture, its name, a line under it and the price; his cash in the corner and a line saying what
## the last thing he did came to. Up / Down and Enter, a row's number, or a click buys it; Esc or E closes.
## It only shows and asks: `chosen` says which row's "id" was picked, `closed` that it went away, and the shop
## does the buying and hands it the rows again (`show_rows`). Every word on it is a placeholder.

signal chosen(id: String)
signal closed

const FONT := preload("res://assets/fonts/Bungee-Regular.ttf")
const PAPER := Color("#f6f1e3")
const TICKET := Color("#f2d24a")
const FAINT := Color(0.96, 0.94, 0.89, 0.62)
const SHORT := Color("#e8392b")
const SHADE := Color(14 / 255.0, 20 / 255.0, 40 / 255.0, 0.98)
const BAND := Color(0.95, 0.82, 0.29, 0.13)      # behind the lit row
## The colour of a box of each weapon's rounds (their picture is drawn here: the weapons have pictures, their rounds do not).
const BOXES := {"pistol": Color(0.78, 0.14, 0.12), "uzi": Color(0.2, 0.42, 0.24), "ak": Color(0.92, 0.7, 0.14)}

static var _boxes := {}        # weapon: the picture of a box of its rounds

var rows: Array = []           # each {"id", "weapon", "name", "note", "price"}
var _cash := 0
var _box: VBoxContainer
var _cash_label: Label
var _said: Label
var _names: Array = []         # each row's name
var _bands: Array = []         # each row's band, lit behind it when it is the one
var _dear: Array = []          # each row: true when he is short of its price
var _plain: StyleBoxFlat
var _lit_band: StyleBoxFlat
var _lit := -1


func _init() -> void:
	layer = 11
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.4)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
			close())
	add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = SHADE
	style.set_corner_radius_all(14)
	style.set_border_width_all(4)
	style.border_color = Color("#3a1414")
	style.content_margin_left = 34.0
	style.content_margin_right = 34.0
	style.content_margin_top = 22.0
	style.content_margin_bottom = 20.0
	panel.add_theme_stylebox_override("panel", style)
	centre.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	var title := _label(34, TICKET)
	title.text = "THE COUNTER"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_cash_label = _label(24, PAPER)
	_cash_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_cash_label)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	column.add_child(_box)
	_said = _label(18, TICKET)
	_said.custom_minimum_size = Vector2(0, 26)
	column.add_child(_said)
	var foot := _label(15, FAINT)
	foot.text = "BUY: CLICK, ITS NUMBER, OR UP DOWN AND ENTER     LEAVE: E OR ESC"
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(foot)
	_plain = StyleBoxFlat.new()                      # a row's band: clear, or lit with a yellow edge
	_plain.bg_color = Color(0, 0, 0, 0)
	_plain.set_corner_radius_all(8)
	_plain.content_margin_left = 10.0
	_plain.content_margin_right = 12.0
	_plain.content_margin_top = 2.0
	_plain.content_margin_bottom = 2.0
	_lit_band = _plain.duplicate()
	_lit_band.bg_color = BAND
	_lit_band.border_width_left = 4
	_lit_band.border_color = TICKET
	visible = false


func is_open() -> bool:
	return visible


## Up with these rows and this much cash; `said` is the line under them (what the last thing came to). As it
## opens the top row is lit, so Enter has one to buy; after a buy the light stays on the same row if it is still
## there, else on the same line.
func show_rows(list: Array, cash: int, said := "") -> void:
	var was: String = String(rows[_lit]["id"]) if visible and _lit >= 0 and _lit < rows.size() else ""
	var opening := not visible
	rows = list
	_cash = cash
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	_names = []
	_bands = []
	_dear = []
	for i in rows.size():
		_box.add_child(_row(i))
	if rows.is_empty():
		var none := _label(20, FAINT)
		none.text = "NOTHING FOR YOU TODAY"
		_box.add_child(none)
	_cash_label.text = "CASH  " + _dollars(cash)
	_said.text = said
	var lit := 0 if opening else clampi(_lit, 0, rows.size() - 1)
	for i in rows.size():
		if String(rows[i]["id"]) == was:
			lit = i
	hover(lit if not rows.is_empty() else -1)
	visible = true


func _row(i: int) -> Control:
	var row: Dictionary = rows[i]
	var dear := int(row["price"]) > _cash
	var band := PanelContainer.new()
	band.add_theme_stylebox_override("panel", _plain)
	band.mouse_filter = Control.MOUSE_FILTER_STOP
	band.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	band.mouse_entered.connect(hover.bind(i))
	band.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
			pick(i))
	var box := HBoxContainer.new()
	box.custom_minimum_size = Vector2(0, 64)
	box.add_theme_constant_override("separation", 16)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(box)
	var key := _label(24, TICKET)
	key.text = str(i + 1) if i < 9 else ""
	key.custom_minimum_size = Vector2(28, 0)
	key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(key)
	var picture := TextureRect.new()
	var weapon := String(row["weapon"])
	if String(row["id"]).begins_with("rounds:"):
		picture.texture = _rounds_picture(weapon)
	else:
		picture.texture = load("res://assets/weapons/%s.png" % weapon)
	picture.custom_minimum_size = Vector2(120, 60)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if dear:
		picture.modulate = Color(1, 1, 1, 0.45)
	box.add_child(picture)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_theme_constant_override("separation", 0)
	box.add_child(words)
	var called := _label(24, PAPER)
	called.text = String(row["name"])
	words.add_child(called)
	var line := HBoxContainer.new()                  # the note; and, when he is short, that in red after it
	line.add_theme_constant_override("separation", 0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(line)
	var note := _label(16, FAINT)
	note.text = String(row.get("note", ""))
	line.add_child(note)
	if dear:
		var short := _label(16, SHORT)
		short.text = "  -  NOT ENOUGH CASH"
		line.add_child(short)
	var price := _label(24, SHORT if dear else TICKET)
	price.text = _dollars(int(row["price"]))
	price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(price)
	_names.append(called)
	_bands.append(band)
	_dear.append(dear)
	return band


## A box of a weapon's rounds, 120 x 60 like the weapons' pictures: five rounds standing up out of a card box in
## its colour, a pale band across the box. Rifle rounds are longer. Drawn once for each.
static func _rounds_picture(weapon: String) -> Texture2D:
	if not _boxes.has(weapon):
		var img := Image.create(120, 60, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var ink := Color(0.06, 0.06, 0.08)
		var look: Color = BOXES.get(weapon, Color(0.18, 0.3, 0.6))
		var tall := 30 if weapon == "ak" else 22
		var top := 28 - int(tall * 0.6)                  # the rounds show three fifths of their length over the box
		for k in 5:
			var x := 33 + k * 11
			for o: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:      # an outline
				_round(img, x + o.x, top + o.y, tall, ink, ink)
			_round(img, x, top, tall, Color(0.86, 0.66, 0.26), Color(0.74, 0.42, 0.22))
		img.fill_rect(Rect2i(16, 28, 88, 30), ink)        # the box
		img.fill_rect(Rect2i(18, 30, 84, 26), look)
		img.fill_rect(Rect2i(18, 30, 84, 3), look.lightened(0.25))
		img.fill_rect(Rect2i(18, 38, 84, 10), Color(0.97, 0.95, 0.88))
		_boxes[weapon] = ImageTexture.create_from_image(img)
	return _boxes[weapon]


## One round standing at x, its nose at y = top, `tall` long: a brass case, a copper nose rounded at the tip.
static func _round(img: Image, x: int, top: int, tall: int, brass: Color, nose: Color) -> void:
	img.fill_rect(Rect2i(x, top + 6, 8, tall - 6), brass)
	img.fill_rect(Rect2i(x + 1, top + 1, 6, 5), nose)
	img.fill_rect(Rect2i(x + 2, top, 4, 1), nose)


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


## Light row i (-1: none): its name yellow and a band behind it. A row he cannot pay for keeps its name dim.
func hover(i: int) -> void:
	_lit = i
	for n in _names.size():
		var colour: Color = TICKET if n == i else PAPER
		if _dear[n]:
			colour.a = 0.5
		(_names[n] as Label).add_theme_color_override("font_color", colour)
		(_bands[n] as PanelContainer).add_theme_stylebox_override("panel", _lit_band if n == i else _plain)


## Buy row i (the shop decides whether he can).
func pick(i: int) -> void:
	if visible and i >= 0 and i < rows.size():
		_lit = i
		chosen.emit(String(rows[i]["id"]))


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.pressed:
		return
	get_viewport().set_input_as_handled()        # while the list is up, no key reaches the game
	var key: int = event.physical_keycode
	if event.echo and not key in [KEY_UP, KEY_DOWN]:
		return
	match key:
		KEY_ESCAPE, KEY_E:
			close()
		KEY_UP:
			hover(posmod(_lit - 1, rows.size()) if not rows.is_empty() else -1)
		KEY_DOWN:
			hover(posmod(_lit + 1, rows.size()) if not rows.is_empty() else -1)
		KEY_ENTER, KEY_KP_ENTER:
			pick(_lit)
		_:
			var n := OS.get_keycode_string(key)
			if n.length() == 1 and n >= "1" and n <= "9":
				pick(int(n) - 1)


static func _dollars(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return "$" + digits + out


func _label(size: int, colour: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
