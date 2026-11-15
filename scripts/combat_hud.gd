extends CanvasLayer
## The bottom-left corner while he plays (combat.gd keeps it): his health as a bar, his cash, and what he
## holds as a small picture with its rounds, loaded / spare; nothing weapon-like when his hands are empty.
## Bungee, fat ink outlines, flat colours; drawn for a 900-line screen and scaled to the one there is.
## combat.gd hides it off the game (the title, the choice), while a performance's bars are in and while he
## talks (the talk box runs along the bottom). Redrawn when the player state changes, and while something
## on it moves (the red of a hurt, the bar beating at low health, a reload filling).

const FONT := preload("res://assets/fonts/Bungee-Regular.ttf")
const PlayerState := preload("res://scripts/player_state.gd")
const WEAPONS := "res://assets/weapons/"
const INK := Color(0.03, 0.02, 0.05)
const RED := Color(0.88, 0.15, 0.17)
const RED_LIGHT := Color(1.0, 0.45, 0.42)
const RED_DARK := Color(0.3, 0.06, 0.09)
const GREEN := Color(0.5, 0.86, 0.34)
const CREAM := Color(0.97, 0.94, 0.86)
const LOW := Color(1.0, 0.55, 0.2)
const LOW_HEALTH := 30

var state: RefCounted          # player_state.gd
var weapon := ""               # what he holds ("" nothing)
var reload := -1.0             # 0 .. 1 while he reloads, else below 0
var shown := {}                # what is on it now: "health", "cash", "weapon", "loaded", "spare" (for the check)
var _panel: Control
var _red: ColorRect
var _caption: Label
var _caption_t := 0.0
var _hurt := 0.0               # seconds of red left
var _click := 0.0              # an empty click: the rounds flash
var _time := 0.0
var _pics := {}
var _heart := PackedVector2Array()
var _boxes: Array = []           # StyleBoxFlats, made once and coloured again each time they are drawn
var _used := 0


func _init() -> void:
	layer = 3
	_red = ColorRect.new()
	_red.color = Color(0.85, 0.04, 0.08, 0.0)
	_red.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_red.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_red)
	_panel = Control.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.draw.connect(_draw_hud)
	add_child(_panel)
	_caption = Label.new()
	_caption.add_theme_font_override("font", FONT)
	_caption.add_theme_font_size_override("font_size", 30)
	_caption.add_theme_color_override("font_color", CREAM)
	_caption.add_theme_color_override("font_outline_color", INK)
	_caption.add_theme_constant_override("outline_size", 10)
	_caption.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_caption.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_caption.offset_top = 90.0
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.visible = false
	add_child(_caption)
	for i in 28:                   # a heart, 1 across
		var t := TAU * float(i) / 28.0
		_heart.append(Vector2(pow(sin(t), 3.0), -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)) / 16.0) * 0.5)


func watch(player_state: RefCounted) -> void:
	state = player_state
	state.changed.connect(_panel.queue_redraw)
	_panel.queue_redraw()


## He is hurt: the screen goes red for a moment.
func hurt() -> void:
	_hurt = 0.45


## He pulled the trigger on an empty gun.
func click() -> void:
	_click = 0.5


## A line across the top for a few seconds (the hospital bill).
func caption(text: String, seconds := 4.0) -> void:
	_caption.text = text
	_caption.visible = true
	_caption_t = seconds


func tick(delta: float) -> void:
	_time += delta
	var moving := _hurt > 0.0 or _click > 0.0 or reload >= 0.0
	_hurt = maxf(_hurt - delta, 0.0)
	_click = maxf(_click - delta, 0.0)
	_red.color.a = 0.42 * smoothstep(0.0, 0.45, _hurt)
	if _caption_t > 0.0:
		_caption_t -= delta
		_caption.visible = _caption_t > 0.0
	if state and int(state.health) <= LOW_HEALTH and int(state.health) > 0:
		moving = true
	if moving or _panel.get_meta("weapon_was", "") != weapon:
		_panel.set_meta("weapon_was", weapon)
		_panel.queue_redraw()


func _pic(weapon_name: String) -> Texture2D:
	if not _pics.has(weapon_name):
		var path := WEAPONS + weapon_name + ".png"
		_pics[weapon_name] = load(path) if ResourceLoader.exists(path) else null
	return _pics[weapon_name]


func _text(at: Vector2, text: String, size: float, color: Color, k: float) -> float:
	var s := int(round(size * k))
	_panel.draw_string_outline(FONT, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, s, int(round(8.0 * k)), INK)
	_panel.draw_string(FONT, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, s, color)
	return FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x


static func dollars(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-$" if n < 0 else "$") + digits + out


func _box(rect: Rect2, color: Color, radius: float) -> void:
	if _used >= _boxes.size():
		var made := StyleBoxFlat.new()
		made.anti_aliasing = true
		_boxes.append(made)
	var box: StyleBoxFlat = _boxes[_used]
	_used += 1
	box.bg_color = color
	box.set_corner_radius_all(int(round(radius)))
	_panel.draw_style_box(box, rect)


func _draw_hud() -> void:
	if state == null:
		return
	_used = 0
	var size := _panel.get_viewport_rect().size
	var k := size.y / 900.0
	var x := 30.0 * k
	var health := int(state.health)
	var cash := int(state.cash)
	shown = {"health": health, "cash": cash, "weapon": weapon}

	# Health: a heart and a bar.
	var bar := Rect2(x + 50.0 * k, size.y - 54.0 * k, 250.0 * k, 26.0 * k)
	var heart := Vector2(x + 20.0 * k, bar.get_center().y + 1.0 * k)
	var ink := PackedVector2Array()
	var red := PackedVector2Array()
	for p: Vector2 in _heart:
		ink.append(heart + p * 46.0 * k)
		red.append(heart + p * 34.0 * k)
	_panel.draw_colored_polygon(ink, INK)
	_panel.draw_colored_polygon(red, RED)
	_box(bar.grow(4.0 * k), INK, 9.0 * k)
	_box(bar, RED_DARK, 6.0 * k)
	var full := clampf(float(health) / 100.0, 0.0, 1.0)
	if full > 0.0:
		var fill := Rect2(bar.position, Vector2(maxf(bar.size.x * full, 10.0 * k), bar.size.y))
		var beat := 0.5 + 0.5 * sin(_time * 9.0) if health <= LOW_HEALTH else 0.0
		_box(fill, RED.lerp(RED_LIGHT, beat * 0.7), 6.0 * k)
		_box(Rect2(fill.position + Vector2(5.0, 4.0) * k, Vector2(maxf(fill.size.x - 10.0 * k, 0.0), 5.0 * k)), RED_LIGHT, 2.5 * k)

	# Cash.
	_text(Vector2(x, bar.position.y - 16.0 * k), dollars(cash), 30.0, GREEN, k)

	# What he holds: its picture and its rounds.
	if weapon == "":
		return
	var loaded := int(state.loaded.get(weapon, 0))
	var spare := int(state.spare.get(weapon, 0))
	shown["loaded"] = loaded
	shown["spare"] = spare
	var pic := _pic(weapon)
	var row := bar.position.y - 72.0 * k             # the bottom of the weapon's row
	var right := x
	if pic:
		var h := 52.0 * k
		var w := minf(h * float(pic.get_width()) / float(pic.get_height()), 168.0 * k)
		h = w * float(pic.get_height()) / float(pic.get_width())
		_panel.draw_texture_rect(pic, Rect2(Vector2(x, row - h), Vector2(w, h)), false)
		right = x + w + 14.0 * k
	var clip := int(PlayerState.CLIP.get(weapon, 1))
	var colour := CREAM
	if _click > 0.0 and fmod(_click, 0.2) > 0.1:
		colour = RED_LIGHT
	elif loaded * 4 <= clip:
		colour = LOW
	var base := row - 6.0 * k
	right += _text(Vector2(right, base), str(loaded), 38.0, colour, k)
	right += _text(Vector2(right + 6.0 * k, base), "/ %d" % spare, 22.0, CREAM, k) + 6.0 * k
	if reload >= 0.0:
		var track := Rect2(Vector2(x, row + 4.0 * k), Vector2(right - x, 7.0 * k))
		_box(track.grow(3.0 * k), INK, 5.0 * k)
		_box(Rect2(track.position, Vector2(track.size.x * clampf(reload, 0.0, 1.0), track.size.y)), CREAM, 3.0 * k)
	elif loaded == 0 and spare > 0:
		_text(Vector2(right + 12.0 * k, base), "R  RELOAD", 18.0, LOW, k)
