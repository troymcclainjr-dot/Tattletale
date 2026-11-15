extends CanvasLayer
## The premiere, back at the studio: the video on a screen, a few moments
## from it frozen with a caption each; beside it the stars, the views ticking
## up and the comments coming in; at the end what it looked like, how much
## chaos there was, what it cost and what it paid. Enter (or a click) goes on to
## the next moment, then to the money, then back to the game; Esc goes
## straight to the end (the video is kept and paid for either way).
##
##   premiere.open(result, moments, words, title)     finished

signal finished

const FONT := preload("res://assets/fonts/Bungee-Regular.ttf")
const PAPER := Color("#f6f1e3")
const TICKET := Color("#f2d24a")
const INK := Color("#1c1a22")
const FAINT := Color(0.96, 0.94, 0.89, 0.5)
const SHADE := Color(14 / 255.0, 20 / 255.0, 40 / 255.0, 0.95)
const TICK_TIME := 6.0           # seconds the view count takes to reach its number
const COMMENT_EVERY := 1.1       # seconds between comments coming in

var moment := 0                  # the moment on the screen
var at_end := false              # showing the money

var _result := {}
var _moments: Array = []
var _words := {}
var _t := 0.0
var _screen: TextureRect
var _caption: Label
var _count: Label
var _title: Label
var _head: Label
var _stars: Control
var _views: Label
var _views_name: Label
var _comments: VBoxContainer
var _numbers: Label
var _money: Label
var _paid: Label
var _hint: Label


func _init() -> void:
	layer = 12
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_click)
	add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1480, 800)
	var box := StyleBoxFlat.new()
	box.bg_color = SHADE
	box.set_corner_radius_all(16)
	box.set_border_width_all(4)
	box.border_color = Color("#14203f")
	box.content_margin_left = 36.0
	box.content_margin_right = 36.0
	box.content_margin_top = 24.0
	box.content_margin_bottom = 22.0
	panel.add_theme_stylebox_override("panel", box)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	var head := HBoxContainer.new()
	column.add_child(head)
	_head = _label(40, TICKET)
	_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_head)
	_title = _label(24, PAPER)
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_title)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 34)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	body.add_child(left)
	var tv := PanelContainer.new()
	var bezel := StyleBoxFlat.new()
	bezel.bg_color = Color(0.1, 0.1, 0.12)
	bezel.set_corner_radius_all(18)
	bezel.set_border_width_all(6)
	bezel.border_color = Color(0.03, 0.03, 0.04)
	bezel.content_margin_left = 16.0
	bezel.content_margin_right = 16.0
	bezel.content_margin_top = 16.0
	bezel.content_margin_bottom = 16.0
	bezel.shadow_color = Color(0, 0, 0, 0.5)
	bezel.shadow_size = 8
	bezel.shadow_offset = Vector2(5, 6)
	tv.add_theme_stylebox_override("panel", bezel)
	left.add_child(tv)
	_screen = TextureRect.new()
	_screen.custom_minimum_size = Vector2(800, 450)
	_screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_screen.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tv.add_child(_screen)
	var strip := PanelContainer.new()
	var paper := StyleBoxFlat.new()
	paper.bg_color = PAPER
	paper.set_corner_radius_all(6)
	paper.set_border_width_all(3)
	paper.border_color = INK
	paper.content_margin_left = 18.0
	paper.content_margin_right = 18.0
	paper.content_margin_top = 10.0
	paper.content_margin_bottom = 10.0
	paper.shadow_color = Color(0, 0, 0, 0.45)
	paper.shadow_size = 4
	paper.shadow_offset = Vector2(3, 4)
	strip.add_theme_stylebox_override("panel", paper)
	left.add_child(strip)
	var strip_row := HBoxContainer.new()
	strip.add_child(strip_row)
	_caption = Label.new()
	_caption.add_theme_font_override("font", FONT)
	_caption.add_theme_font_size_override("font_size", 26)
	_caption.add_theme_color_override("font_color", INK)
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip_row.add_child(_caption)
	_count = Label.new()
	_count.add_theme_font_override("font", FONT)
	_count.add_theme_font_size_override("font_size", 18)
	_count.add_theme_color_override("font_color", Color(INK, 0.6))
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strip_row.add_child(_count)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	_stars = Stars.new()
	_stars.custom_minimum_size = Vector2(300, 52)
	right.add_child(_stars)
	_views_name = _label(18, FAINT)
	right.add_child(_views_name)
	_views = _label(56, PAPER)
	right.add_child(_views)
	_comments = VBoxContainer.new()
	_comments.add_theme_constant_override("separation", 8)
	_comments.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_comments)
	_numbers = _label(22, PAPER)
	right.add_child(_numbers)
	_money = _label(22, PAPER)
	right.add_child(_money)
	_paid = _label(40, TICKET)
	right.add_child(_paid)

	_hint = _label(18, FAINT)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(_hint)


func is_open() -> bool:
	return visible


## `result` is video_score.gd's result (and "title", "where"); `moments` each
## {"caption", "image" (an Image)}.
func open(result: Dictionary, moments: Array, words: Dictionary, title: String) -> void:
	_result = result
	_moments = moments
	_words = words
	_t = 0.0
	moment = 0
	at_end = false
	_head.text = String(words.get("premiere", "WORLD PREMIERE"))
	_title.text = title
	_views_name.text = String(words.get("views", "VIEWS"))
	(_stars as Stars).count = int(result.get("stars", 1))
	_stars.queue_redraw()
	for child in _comments.get_children():
		_comments.remove_child(child)
		child.queue_free()
	for c: Dictionary in result.get("comments", []):
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		var who := _label(16, TICKET)
		who.text = "@" + String(c["who"])
		row.add_child(who)
		var text := _label(21, PAPER)
		text.text = String(c["text"])
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(520, 0)
		row.add_child(text)
		row.visible = false
		_comments.add_child(row)
	_numbers.text = "%s %d     %s %d     %s %d" % [words.get("looks", "LOOKS"), result.get("looks", 0), words.get("swagger", "SWAGGER"), result.get("swagger", 0), words.get("chaos", "CHAOS"), result.get("chaos", 0)]
	_money.text = "%s  %s" % [words.get("spent", "SPENT"), _dollars(int(result.get("spent", 0)))]
	_paid.text = "%s  %s" % [words.get("paid", "PAID"), _dollars(int(result.get("paid", 0)))]
	_show_moment()
	visible = true
	_refresh()


func close() -> void:
	visible = false


## Enter: the next moment; after the last, the money; after that, done.
func next() -> void:
	if not visible:
		return
	if at_end:
		visible = false
		finished.emit()
	elif moment < _moments.size() - 1:
		moment += 1
		_show_moment()
	else:
		results()


## Straight to the money: the views counted, every comment in.
func results() -> void:
	at_end = true
	_t = maxf(_t, TICK_TIME + COMMENT_EVERY * (_comments.get_child_count() + 1))
	if not _moments.is_empty():
		moment = _moments.size() - 1
		_show_moment()
	_refresh()


func _show_moment() -> void:
	if _moments.is_empty():
		_screen.texture = null
		_caption.text = ""
		_count.text = ""
		return
	var m: Dictionary = _moments[moment]
	var image: Image = m.get("image")
	_screen.texture = ImageTexture.create_from_image(image) if image else null
	_caption.text = String(m.get("caption", ""))
	_count.text = "%d / %d" % [moment + 1, _moments.size()]


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_refresh()


func _refresh() -> void:
	var k := clampf(_t / TICK_TIME, 0.0, 1.0)
	var shown := roundi(float(_result.get("views", 0)) * (1.0 - pow(1.0 - k, 3.0)))
	_views.text = _commas(shown)
	for i in _comments.get_child_count():
		(_comments.get_child(i) as Control).visible = _t >= 1.0 + COMMENT_EVERY * i
	_numbers.visible = at_end
	_money.visible = at_end
	_paid.visible = at_end
	_hint.text = String(_words.get("done", "")) if at_end else "%s        %s" % [_words.get("next", ""), _words.get("skip", "ESC  SKIP")]


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	match event.physical_keycode:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_E:
			next()
		KEY_ESCAPE:
			visible = false
			finished.emit()


func _on_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		next()


static func _commas(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return out


static func _dollars(n: int) -> String:
	return "$" + _commas(n)


func _label(size: int, colour: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Five stars, the first `count` filled in.
class Stars extends Control:
	var count := 0

	func _draw() -> void:
		for i in 5:
			var mid := Vector2(26.0 + i * 56.0, size.y * 0.5)
			var points := PackedVector2Array()
			for k in 10:
				var r := 24.0 if k % 2 == 0 else 10.0
				var a := -PI * 0.5 + k * PI / 5.0
				points.append(mid + Vector2(cos(a), sin(a)) * r)
			if i < count:
				draw_colored_polygon(points, Color("#f2d24a"))
			else:
				draw_colored_polygon(points, Color(1, 1, 1, 0.1))
			var ring := points.duplicate()
			ring.append(points[0])
			draw_polyline(ring, Color.BLACK, 3.0, true)
