extends CanvasLayer
## The top-right corner while he plays: his standing (respect, heat, trust: street.gd), what he carries and owes
## (dealing.gd), and in a fight the two winds (melee.gd). Drawn for a 900-line screen and scaled to the one there
## is, in the bottom-left corner's manner (combat_hud.gd). Every word on it is a placeholder.

const FONT := preload("res://assets/fonts/Bungee-Regular.ttf")
const Street := preload("res://scripts/street.gd")
const INK := Color(0.03, 0.02, 0.05)
const CREAM := Color(0.97, 0.94, 0.86)
const GOLD := Color(0.98, 0.78, 0.22)
const RED := Color(0.88, 0.15, 0.17)
const BLUE := Color(0.36, 0.62, 0.95)
const GREEN := Color(0.5, 0.86, 0.34)
const DARK := Color(0.12, 0.1, 0.16)
const COLOUR := {"respect": GOLD, "heat": RED, "trust": BLUE}
const LABEL := {"respect": "RESPECT", "heat": "HEAT", "trust": "TRUST"}

var state: RefCounted
var lines: Array = []           # dealing.gd's lines under the three numbers ("CARRYING ...", "OWES ...")
var fight := {}                 # melee.gd: {"mine": 0..1, "his": 0..1, "name": "TRE", "note": "SLIP"} while he has his hands up
var shown := {}                 # what is on it now (for the steps)
var _panel: Control
var _was := {}                  # the three numbers when last drawn
var _flash := {}                # kind: seconds a change stays lit
var _by := {}                   # kind: the last change


func _init() -> void:
	layer = 3
	_panel = Control.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.draw.connect(_draw_it)
	add_child(_panel)


func tick(delta: float) -> void:
	if state == null:
		return
	for kind: String in Street.KINDS:
		var now := Street.value(state, kind)
		if _was.has(kind) and int(_was[kind]) != now:
			_by[kind] = now - int(_was[kind])
			_flash[kind] = 3.0
		_was[kind] = now
		_flash[kind] = maxf(float(_flash.get(kind, 0.0)) - delta, 0.0)
	_panel.queue_redraw()


func _text(at: Vector2, text: String, size: float, colour: Color, k: float, right := false) -> float:
	var px := int(round(size * k))
	var w := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var p := at - Vector2(w, 0.0) if right else at
	_panel.draw_string_outline(FONT, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, int(round(8.0 * k)), INK)
	_panel.draw_string(FONT, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, colour)
	return w


func _bar(rect: Rect2, full: float, colour: Color, k: float) -> void:
	_panel.draw_rect(rect.grow(4.0 * k), INK)
	_panel.draw_rect(rect, DARK)
	if full > 0.0:
		_panel.draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(full, 0.0, 1.0), rect.size.y)), colour)


func _draw_it() -> void:
	if state == null:
		return
	var size := _panel.get_viewport_rect().size
	var k := size.y / 900.0
	var right := size.x - 30.0 * k
	var y := 44.0 * k
	shown = {"lines": lines.duplicate()}
	for kind: String in Street.KINDS:
		var now := Street.value(state, kind)
		shown[kind] = now
		var lit := float(_flash.get(kind, 0.0)) > 0.0
		var text := "%s %d" % [LABEL[kind], now]
		if lit:
			text += "  %+d" % int(_by.get(kind, 0))
		_text(Vector2(right, y), text, 20.0 if not lit else 24.0, COLOUR[kind] if lit else CREAM, k, true)
		y += 28.0 * k
	for line: String in lines:
		_text(Vector2(right, y), line, 17.0, GREEN, k, true)
		y += 24.0 * k
	if fight.is_empty():
		return
	# A fight: his wind bottom-left over his health, the other man's across the top with his name.
	_bar(Rect2(98.0 * k, size.y - 138.0 * k, 232.0 * k, 14.0 * k), float(fight.get("mine", 1.0)), GOLD, k)
	_text(Vector2(30.0 * k, size.y - 125.0 * k), "WIND", 16.0, CREAM, k)
	if fight.has("his"):
		var w := 360.0 * k
		var top := Rect2((size.x - w) * 0.5, 64.0 * k, w, 16.0 * k)
		_bar(top, float(fight["his"]), RED, k)
		var who := String(fight.get("name", ""))
		var half := FONT.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(20.0 * k))).x * 0.5
		_text(Vector2(size.x * 0.5 - half, 52.0 * k), who, 20.0, CREAM, k)
	var note := String(fight.get("note", ""))
	if note != "":
		var half := FONT.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(26.0 * k))).x * 0.5
		_text(Vector2(size.x * 0.5 - half, 124.0 * k), note, 26.0, GOLD, k)
