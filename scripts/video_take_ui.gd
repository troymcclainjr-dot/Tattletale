extends CanvasLayer
## What is over the picture during a take: the camcorder's viewfinder (its
## corners, REC, the time code, the battery) with brackets round the part of the
## frame he must stay in (white while he is in it, red when he is not); the
## SWAGGER and CHAOS meters; the lane along the bottom where the moves come in
## from the right, each a key in a circle, to be pressed as it reaches the ring
## on the left (a mark on the lane for every beat of the music, a longer one on
## each bar, comes in with them; the next move is the brightest; through the
## count-in the ring counts the bar, 1 2 3 4); how each press went; the mishap card (what is going wrong, and
## the key that deals with it); the voice of someone off the picture; and the
## big words of the count-in and the wrap. video_take.gd tells it what to show.

const FONT := preload("res://assets/fonts/Bungee-Regular.ttf")
const PAPER := Color("#f6f1e3")
const TICKET := Color("#f2d24a")
const INK := Color("#1c1a22")
const FAINT := Color(0.96, 0.94, 0.89, 0.5)
const SHADE := Color(14 / 255.0, 20 / 255.0, 40 / 255.0, 0.9)
const RED := Color("#e8392b")
const CHAOS := Color("#f07a2a")
const HIT_X := 230.0           # the ring the moves are pressed at, from the left
const LANE_Y := 92.0           # and from the bottom
const PER_BEAT := 300.0        # pixels a move comes in by each beat
const POOL := 14

var finder := 0.0              # how much of the viewfinder shows, 0 .. 1
var in_shot := true
var frame := 0.24              # the part of the frame he must stay in: this much of the width each side of the middle
var swagger := 0.0
var chaos := 0.0
var rec_on := 1.0              # the red dot by REC, blinking
var pulse := 0.0               # 1 on each beat of the music, falling away: the ring swells with it
var count := 0                 # through the count-in, which beat of it (1 .. 4), shown in the ring; 0: none
var grid_end := 1.0e6          # the take's last beat of music: no beat marks past it
var words := {}
var _now := 0.0                # the take's beat, for the beat marks

var _draw_node: Control
var _rec: Label
var _code: Label
var _section: Label
var _big: Label
var _judge: Label
var _judge_t := 9.0
var _out: Label
var _keys: Label
var _title: Label
var _prompts: Array = []       # the pool: each {"box": Panel, "key": Label, "name": Label}
var _card: PanelContainer
var _card_name: Label
var _card_keys: Label
var _card_bar: ColorRect
var _voice: PanelContainer
var _voice_who: Label
var _voice_line: Label
var _clock := 0.0


func _init() -> void:
	layer = 6
	visible = false
	_draw_node = Finder.new()
	_draw_node.ui = self
	_draw_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_draw_node)
	_rec = _label(26, PAPER)
	_rec.position = Vector2(92, 46)
	add_child(_rec)
	_title = _label(18, FAINT)
	_title.position = Vector2(92, 82)
	add_child(_title)
	_code = _label(26, PAPER)
	_at(_code, Control.PRESET_TOP_RIGHT, -330, 46, -80, 86)
	_code.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_code)
	_section = _label(18, FAINT)
	_at(_section, Control.PRESET_CENTER_TOP, -150, 100, 150, 130)
	_section.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_section)
	_out = _label(30, RED)
	_at(_out, Control.PRESET_CENTER, -300, -262, 300, -212)
	_out.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_out)
	_big = _label(72, TICKET)
	_at(_big, Control.PRESET_CENTER, -700, -300, 700, -190)
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big.add_theme_constant_override("outline_size", 14)
	add_child(_big)
	_keys = _label(15, FAINT)
	_at(_keys, Control.PRESET_BOTTOM_RIGHT, -760, -34, -60, -10)
	_keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_keys)
	for i in POOL:
		var tail := Panel.new()         # hard: a hold prompt's tail, as long as the hold, behind its box
		var tail_look := StyleBoxFlat.new()
		tail_look.bg_color = Color(PAPER, 0.75)
		tail_look.set_corner_radius_all(12)
		tail_look.set_border_width_all(3)
		tail_look.border_color = INK
		tail.add_theme_stylebox_override("panel", tail_look)
		tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tail.visible = false
		add_child(tail)
		var box := Panel.new()
		box.size = Vector2(68, 68)
		var look := StyleBoxFlat.new()
		look.bg_color = PAPER
		look.set_corner_radius_all(34)
		look.set_border_width_all(4)
		look.border_color = INK
		look.shadow_color = Color(0, 0, 0, 0.5)
		look.shadow_size = 3
		look.shadow_offset = Vector2(2, 3)
		box.add_theme_stylebox_override("panel", look)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.visible = false
		add_child(box)
		var key := _label(32, INK)
		key.add_theme_constant_override("outline_size", 0)
		key.size = Vector2(68, 68)
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(key)
		var name_label := _label(14, PAPER)
		name_label.size = Vector2(200, 22)
		name_label.position = Vector2(-66, 72)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(name_label)
		_prompts.append({"box": box, "key": key, "name": name_label, "look": look, "tail": tail, "tail_look": tail_look})
	_judge = _label(30, TICKET)
	_judge.size = Vector2(300, 40)
	add_child(_judge)

	_card = PanelContainer.new()
	_at(_card, Control.PRESET_CENTER_TOP, -330, 146, 330, 146)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.custom_minimum_size = Vector2(660, 0)
	var look := StyleBoxFlat.new()
	look.bg_color = TICKET
	look.set_corner_radius_all(8)
	look.set_border_width_all(5)
	look.border_color = INK
	look.shadow_color = Color(0, 0, 0, 0.5)
	look.shadow_size = 5
	look.shadow_offset = Vector2(4, 5)
	look.content_margin_left = 22.0
	look.content_margin_right = 22.0
	look.content_margin_top = 12.0
	look.content_margin_bottom = 12.0
	_card.add_theme_stylebox_override("panel", look)
	_card.visible = false
	add_child(_card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_card.add_child(column)
	_card_name = _ink(28)
	_card_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_card_name)
	_card_keys = _ink(22)
	_card_keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_card_keys)
	var bar_back := ColorRect.new()
	bar_back.color = Color(0, 0, 0, 0.25)
	bar_back.custom_minimum_size = Vector2(0, 10)
	column.add_child(bar_back)
	_card_bar = ColorRect.new()
	_card_bar.color = INK
	_card_bar.size = Vector2(616, 10)
	bar_back.add_child(_card_bar)

	_voice = PanelContainer.new()
	_at(_voice, Control.PRESET_CENTER_LEFT, 70, -170, 490, -170)
	_voice.custom_minimum_size = Vector2(420, 0)
	var shade := StyleBoxFlat.new()
	shade.bg_color = SHADE
	shade.set_corner_radius_all(14)
	shade.set_border_width_all(4)
	shade.border_color = Color("#14203f")
	shade.content_margin_left = 22.0
	shade.content_margin_right = 22.0
	shade.content_margin_top = 12.0
	shade.content_margin_bottom = 14.0
	_voice.add_theme_stylebox_override("panel", shade)
	_voice.visible = false
	add_child(_voice)
	var lines := VBoxContainer.new()
	_voice.add_child(lines)
	_voice_who = _label(20, TICKET)
	lines.add_child(_voice_who)
	_voice_line = _label(26, PAPER)
	_voice_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_voice_line.custom_minimum_size = Vector2(376, 0)
	lines.add_child(_voice_line)


func open(said: Dictionary, title: String) -> void:
	words = said
	_rec.text = String(words.get("rec", "REC"))
	_title.text = title
	_keys.text = String(words.get("take_keys", ""))
	_out.text = String(words.get("out_of_shot", "OUT OF SHOT"))
	finder = 0.0
	_big.text = ""
	_card.visible = false
	_voice.visible = false
	_judge_t = 9.0
	for p: Dictionary in _prompts:
		(p["box"] as Panel).visible = false
		(p["tail"] as Panel).visible = false
	visible = true


func close() -> void:
	visible = false


func big(text: String, colour := TICKET) -> void:
	_big.text = text
	_big.add_theme_color_override("font_color", colour)


func set_time(seconds: float) -> void:
	var s := maxi(int(seconds), 0)
	_code.text = "%02d:%02d:%02d" % [s / 60, s % 60, int(fposmod(seconds, 1.0) * 24.0)]


func set_section(text: String) -> void:
	_section.text = text


## How a press went: PERFECT, GOOD, MISS, OFF BEAT. It floats up off the ring.
func judge(text: String, colour: Color) -> void:
	_judge.text = text
	_judge.add_theme_color_override("font_color", colour)
	_judge_t = 0.0


## The moves on their way in: each {"beat", "key", "name", "state"} ("due",
## "hit" or "miss"), drawn where they are at beat `now`.
func lane(prompts: Array, now: float) -> void:
	_now = now
	var used := 0
	var next := INF                # the nearest move still to press: it is the brightest
	for p: Dictionary in prompts:
		if p["state"] == "due" and float(p["beat"]) - now >= -0.7:
			next = minf(next, float(p["beat"]))
	var bottom := get_viewport().get_visible_rect().size.y - LANE_Y
	for p: Dictionary in prompts:
		var ahead: float = float(p["beat"]) - now
		var holding := bool(p.get("holding", false))      # hard: being held now: pinned at the ring
		if (ahead > 4.6 or ahead < -0.7 or used >= _prompts.size()) and not (holding and used < _prompts.size()):
			continue
		if p["state"] == "hit" and ahead < -0.25 and not holding:
			continue
		var slot: Dictionary = _prompts[used]
		used += 1
		var box: Panel = slot["box"]
		box.visible = true
		var pop := 1.0 + (0.25 * (1.0 - clampf(-ahead / 0.25, 0.0, 1.0)) if p["state"] == "hit" else 0.0)
		box.scale = Vector2(pop, pop)
		box.pivot_offset = Vector2(34, 34)
		var x := HIT_X + (0.0 if holding else ahead) * PER_BEAT
		box.position = Vector2(x - 34.0, bottom - 34.0)
		var tail: Panel = slot["tail"]
		var hold := float(p.get("hold", 0.0))
		tail.visible = hold > 0.0 and (p["state"] == "due" or holding)
		if tail.visible:
			var left := hold - maxf(-ahead, 0.0) if holding else hold
			tail.position = Vector2(x, bottom - 13.0)
			tail.size = Vector2(maxf(left * PER_BEAT, 4.0), 26.0)
			(slot["tail_look"] as StyleBoxFlat).bg_color = TICKET if holding else Color(PAPER, 0.75)
			tail.modulate.a = 0.72 if p["state"] == "due" and float(p["beat"]) > next else 1.0
		(slot["key"] as Label).text = String(p["key"])
		(slot["name"] as Label).text = String(p["name"])
		var look: StyleBoxFlat = slot["look"]
		look.bg_color = TICKET if p["state"] == "hit" else (Color(0.45, 0.45, 0.5) if p["state"] == "miss" else PAPER)
		box.modulate.a = 0.6 if p["state"] == "miss" else (0.72 if p["state"] == "due" and float(p["beat"]) > next else 1.0)
	for i in range(used, _prompts.size()):
		(_prompts[i]["box"] as Panel).visible = false
		(_prompts[i]["tail"] as Panel).visible = false


## The mishap card: {"name", "say" (the key's line), "or" (what not pressing it
## does), "key", "left" (1 .. 0, the time left to answer)}; empty puts it away.
func mishap(card: Dictionary) -> void:
	_card.visible = not card.is_empty()
	if card.is_empty():
		return
	_card_name.text = String(card.get("name", ""))
	var keys := "%s   %s" % [card.get("key", "E"), card.get("say", "")]
	if String(card.get("or", "")) != "":
		keys += "      %s   %s" % [card.get("or_word", "OR"), card["or"]]
	_card_keys.text = keys
	_card_bar.size = Vector2(616.0 * clampf(float(card.get("left", 1.0)), 0.0, 1.0), 10)


## Someone speaking from off the picture; an empty line puts the box away.
func voice(who: String, line: String) -> void:
	_voice.visible = line != ""
	_voice_who.text = who
	_voice_line.text = line


func _process(delta: float) -> void:
	if not visible:
		return
	_clock += delta
	_judge_t += delta
	var bottom := get_viewport().get_visible_rect().size.y - LANE_Y
	_judge.position = Vector2(HIT_X - 150.0, bottom - 116.0 - 40.0 * minf(_judge_t, 0.6))
	_judge.modulate.a = clampf(1.0 - (_judge_t - 0.35) / 0.35, 0.0, 1.0)
	rec_on = 1.0 if int(_clock * 1.6) % 2 == 0 else 0.2
	_rec.modulate.a = finder
	_title.modulate.a = finder
	_code.modulate.a = finder
	_section.modulate.a = finder
	_out.visible = finder > 0.5 and not in_shot and int(_clock * 3.0) % 2 == 0
	_draw_node.queue_redraw()


## Pin a control to a corner or an edge of the screen, `l`, `t`, `r`, `b` from it.
func _at(c: Control, preset: int, l: float, t: float, r: float, b: float) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = l
	c.offset_top = t
	c.offset_right = r
	c.offset_bottom = b


func _label(size: int, colour: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 7)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _ink(size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", INK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## The lines of the viewfinder, the brackets, the meters and the lane's track.
class Finder extends Control:
	var ui

	func _draw() -> void:
		var s := get_viewport_rect().size
		var a: float = ui.finder
		var white := Color(1, 1, 1, 0.85 * a)
		# The viewfinder's corners.
		var m := Vector2(48, 36)
		var arm := 70.0
		for c: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
			var at := Vector2(m.x if c.x == 0.0 else s.x - m.x, m.y if c.y == 0.0 else s.y - m.y)
			var sx := 1.0 if c.x == 0.0 else -1.0
			var sy := 1.0 if c.y == 0.0 else -1.0
			draw_line(at, at + Vector2(arm * sx, 0), white, 4.0)
			draw_line(at, at + Vector2(0, arm * sy), white, 4.0)
		# The red dot by REC.
		draw_circle(Vector2(74, 63), 11.0, Color(RED, a * ui.rec_on))
		# The middle cross.
		var mid := s * 0.5
		draw_line(mid - Vector2(16, 0), mid + Vector2(16, 0), Color(1, 1, 1, 0.5 * a), 2.0)
		draw_line(mid - Vector2(0, 16), mid + Vector2(0, 16), Color(1, 1, 1, 0.5 * a), 2.0)
		# The battery, top right.
		var b := Vector2(s.x - 96, 92)
		draw_rect(Rect2(b, Vector2(44, 20)), white, false, 3.0)
		draw_rect(Rect2(b + Vector2(44, 6), Vector2(5, 8)), white)
		for k in 3:
			draw_rect(Rect2(b + Vector2(5 + k * 13, 4), Vector2(9, 12)), white)
		# The part of the frame he must stay in.
		var half: float = ui.frame * s.x
		var box := Rect2(mid.x - half, s.y * 0.17, half * 2.0, s.y * 0.6)
		var look := Color(1, 1, 1, 0.6 * a) if ui.in_shot else Color(0.95, 0.2, 0.15, 0.9 * a)
		var ticks := 34.0
		for c: Vector2 in [box.position, Vector2(box.end.x, box.position.y), Vector2(box.position.x, box.end.y), box.end]:
			var sx := 1.0 if c.x < mid.x else -1.0
			var sy := 1.0 if c.y < mid.y else -1.0
			draw_line(c, c + Vector2(ticks * sx, 0), look, 3.0)
			draw_line(c, c + Vector2(0, ticks * sy), look, 3.0)
		# The meters, top middle: swagger and chaos.
		var w := 260.0
		var top := 46.0
		var font: Font = FONT
		for k in 2:
			var x := mid.x - w - 20.0 if k == 0 else mid.x + 20.0
			var value: float = ui.swagger if k == 0 else ui.chaos
			var fill := TICKET if k == 0 else CHAOS
			var said := String(ui.words.get("swagger", "SWAGGER")) if k == 0 else String(ui.words.get("chaos", "CHAOS"))
			draw_string_outline(font, Vector2(x, top + 2), said, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 6, Color(0, 0, 0, a))
			draw_string(font, Vector2(x, top + 2), said, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(PAPER, a))
			draw_rect(Rect2(Vector2(x, top + 10), Vector2(w, 16)), Color(0, 0, 0, 0.55 * a))
			draw_rect(Rect2(Vector2(x, top + 10), Vector2(w * clampf(value / 100.0, 0.0, 1.0), 16)), Color(fill, a))
			draw_rect(Rect2(Vector2(x, top + 10), Vector2(w, 16)), Color(0, 0, 0, a), false, 2.0)
		# The lane along the bottom, and its ring.
		var y := s.y - LANE_Y
		draw_rect(Rect2(Vector2(0, y - 48), Vector2(s.x, 96)), Color(0.02, 0.02, 0.05, 0.45))
		draw_line(Vector2(0, y - 48), Vector2(s.x, y - 48), Color(1, 1, 1, 0.18), 2.0)
		# The music's beats coming in along it with the moves (each reaches the ring as it sounds), a longer mark on each bar.
		var now: float = ui._now
		for k in range(maxi(ceili(now - 0.8), 0), mini(floori(now + 5.0), floori(ui.grid_end)) + 1):
			var x := HIT_X + (float(k) - now) * PER_BEAT
			var bar := posmod(k, 4) == 0
			var h := 30.0 if bar else 14.0
			draw_line(Vector2(x, y - h), Vector2(x, y + h), Color(1, 1, 1, 0.42 if bar else 0.26), 3.0 if bar else 2.0)
		var swell := 6.0 * float(ui.pulse)
		draw_arc(Vector2(HIT_X, y), 42.0 + swell, 0.0, TAU, 40, TICKET, 5.0 + 0.5 * swell)
		draw_arc(Vector2(HIT_X, y), 48.0 + swell, 0.0, TAU, 40, Color(0, 0, 0, 0.6), 2.0)
		if int(ui.count) > 0:
			var pt := 40 + int(10.0 * float(ui.pulse))
			var spot := Vector2(HIT_X - 60.0, y + 0.36 * pt)
			draw_string_outline(FONT, spot, str(ui.count), HORIZONTAL_ALIGNMENT_CENTER, 120, pt, 8, Color.BLACK)
			draw_string(FONT, spot, str(ui.count), HORIZONTAL_ALIGNMENT_CENTER, 120, pt, TICKET)
