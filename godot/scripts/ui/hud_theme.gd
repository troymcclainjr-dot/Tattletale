extends RefCounted
## The HUD look, from css/style.css: palette, fonts, label settings, boxes, the Theme and a few
## builder helpers. Static only: `const T := preload("res://scripts/ui/hud_theme.gd")`.
##
## Fonts: the web uses Bungee, Barlow Condensed and Courier Prime (Google Fonts). If their TTF/OTF
## files are dropped into res://assets/fonts/ (or res://assets/ui/fonts/) under the Google file
## names (Bungee-Regular.ttf, BarlowCondensed-SemiBold.ttf, CourierPrime-Bold.ttf...) they are
## used; otherwise a SystemFont with the CSS fallback list is.

const Box := preload("res://scripts/ui/hud_box.gd")

# ---- palette (:root) ------------------------------------------------------------------
const INK := Color("#14203f")
const TICKET := Color("#f2d24a")
const PAPER := Color("#f6f1e3")
const SIREN := Color("#d0182e")
const COP := Color("#2c5bd6")
const ASPHALT := Color("#24252b")
const GO := Color("#2f9e5b")
const SHADE := Color(14 / 255.0, 20 / 255.0, 40 / 255.0, 0.78)
const DIM := Color("#c9c3b2")
const KEYS_TEXT := Color("#e9e3d2")
const KBD_EDGE := Color("#6a7290")
const BINO_TOP := Color("#d8d2c0")
const SUB_P := Color("#d9d3c1")
const GARY := Color("#8a7a5a")
const GARY_CHIP := Color("#6a5a3a")
const MENU_Q := Color("#ebe4cf")
const PLATE_BG := Color("#f4f4ee")
const WIRE := Color("#7a84a0")
const WIRE_HOVER := Color("#22325e")
const KEY_SHADOW := Color("#0a1020")
const RULER := Color("#ead9a6")
const RED := Color("#ff3b4e")          # mini-map "spy" dot
const BLUE_DOT := Color("#6aa0ff")     # mini-map phones, mailbox, dispatched
const BLACK := Color(0, 0, 0)

static func a(c: Color, alpha: float) -> Color:
	return Color(c.r, c.g, c.b, alpha)


# ---- fonts ----------------------------------------------------------------------------
const FONT_DIRS := ["res://assets/fonts/", "res://assets/ui/fonts/"]
const FONT_FILES := {
	"display": ["Bungee-Regular"],
	"body500": ["BarlowCondensed-Medium"],
	"body600": ["BarlowCondensed-SemiBold"],
	"body700": ["BarlowCondensed-Bold"],
	"mono": ["CourierPrime-Regular"],
	"monob": ["CourierPrime-Bold"],
}
# On Windows "Arial Black" is only found as family "Arial" at weight 900 (it is the closest
# system match to Bungee's width; Impact is far narrower).
const DISPLAY_NAMES := ["Bungee", "Arial", "Impact", "sans-serif"]
const BODY_NAMES := ["Barlow Condensed", "Bahnschrift", "Arial Narrow", "sans-serif"]
const MONO_NAMES := ["Courier Prime", "Courier New", "monospace"]
## Monochrome symbols (☎ ∞ ⌫) before the system fallback, which would pick a colour emoji font.
const SYMBOL_NAMES := ["Segoe UI Symbol", "Noto Sans Symbols 2", "Noto Sans Symbols", "DejaVu Sans", "sans-serif"]

static var _fonts := {}
static var _symbols: Font
static var _spaced := {}
static var _real := {}   # kind -> true when a real font file was found


## kind: "display" | "body500" | "body600" | "body700" | "mono" | "monob"
static func font(kind: String) -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var f: Font = null
	for dir in FONT_DIRS:
		for base in FONT_FILES.get(kind, []):
			for ext in [".ttf", ".otf", ".woff2", ".woff"]:
				var p: String = dir + base + ext
				if ResourceLoader.exists(p):
					f = load(p)
					if f:
						_real[kind] = true
						break
			if f:
				break
		if f:
			break
	if f == null:
		var s := SystemFont.new()
		match kind:
			"display":
				s.font_names = PackedStringArray(DISPLAY_NAMES)
				s.font_weight = 900
			"body500", "body600", "body700":
				s.font_names = PackedStringArray(BODY_NAMES)
				s.font_weight = int(kind.substr(4))
				s.font_stretch = 75
			"mono":
				s.font_names = PackedStringArray(MONO_NAMES)
				s.font_weight = 400
			"monob":
				s.font_names = PackedStringArray(MONO_NAMES)
				s.font_weight = 700
		s.allow_system_fallback = true
		s.hinting = TextServer.HINTING_LIGHT
		s.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
		f = s
		# Courier New is much thinner than Courier Prime: thicken the fallback a little.
		if kind == "mono" or kind == "monob":
			var v := FontVariation.new()
			v.base_font = s
			v.variation_embolden = 0.35 if kind == "mono" else 0.2
			f = v
	# (No symbol fallback attached here: Godot sizes lines by the tallest font in the
	# fallback chain, so a fallback would make every label taller. Use symbols() directly.)
	_fonts[kind] = f
	return f


static func symbols() -> Font:
	if _symbols == null:
		var s := SystemFont.new()
		s.font_names = PackedStringArray(SYMBOL_NAMES)
		s.allow_system_fallback = true
		_symbols = s
	return _symbols


static func display() -> Font:
	return font("display")


## The display font for one size. CSS letter-spacing in px; when the real Bungee file is
## missing, the Arial Black fallback is also tightened by 0.04em from 18 px up (it is ~10% wider
## than Bungee), so lines break about where the web's do.
static func disp(size: int, letter_px := 0.0) -> Font:
	var f := display()
	var tighten := 0.0 if (_real.get("display", false) or size < 18) else roundf(size * 0.04)
	return spaced(f, letter_px - tighten)


static func body(weight := 600) -> Font:
	return font("body%d" % clampi(weight, 500, 700))


static func mono(bold := false) -> Font:
	return font("monob" if bold else "mono")


## CSS letter-spacing in px (rounded): a FontVariation over the base font.
static func spaced(base: Font, px: float) -> Font:
	var n := int(round(px))
	if n == 0:
		return base
	var key := "%d|%d" % [base.get_instance_id(), n]
	if _spaced.has(key):
		return _spaced[key]
	var v := FontVariation.new()
	v.base_font = base
	v.spacing_glyph = n
	_spaced[key] = v
	return v


static var WJ: String = String.chr(0x2060)   # WORD JOINER: no line break here, renders as nothing


## Display texts: Bungee only has capitals, so the fallback gets upper-cased text too.
## Hyphens are glued (word joiners) so "2-PACK" never wraps as "2-" / "PACK".
static func caps(s: String) -> String:
	return glue(s.to_upper())


static func glue(s: String) -> String:
	return s.replace("-", WJ + "-" + WJ)


# ---- label settings -------------------------------------------------------------------
## shadows: Array of [offset: Vector2, color: Color, outline: int]; the first one is the main
## shadow, the rest are stacked behind it. line_height: CSS line-height multiplier (0 = font's).
static func ls(f: Font, size: int, color: Color, shadows: Array = [], line_height := 0.0, outline := 0, outline_color := Color(0, 0, 0, 0)) -> LabelSettings:
	var s := LabelSettings.new()
	s.font = f
	s.font_size = size
	s.font_color = color
	s.line_spacing = 0.0
	if line_height > 0.0:
		var natural := f.get_height(size)
		s.line_spacing = size * line_height - natural
	if shadows.size() > 0:
		var sh: Array = shadows[0]
		s.shadow_offset = sh[0]
		s.shadow_color = sh[1]
		s.shadow_size = sh[2] if sh.size() > 2 else 0
		for i in range(1, shadows.size()):
			var st: Array = shadows[i]
			s.add_stacked_shadow()
			var k := s.stacked_shadow_count - 1
			s.set_stacked_shadow_offset(k, st[0])
			s.set_stacked_shadow_color(k, st[1])
			s.set_stacked_shadow_outline_size(k, st[2] if st.size() > 2 else 0)
	else:
		s.shadow_color = Color(0, 0, 0, 0)
	if outline > 0:
		s.outline_size = outline
		s.outline_color = outline_color
	return s


# ---- builders -------------------------------------------------------------------------
static func label(text: String, settings: LabelSettings, align := HORIZONTAL_ALIGNMENT_LEFT, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.label_settings = settings
	l.horizontal_alignment = align
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func panel(style: StyleBox, child: Control = null) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if child:
		p.add_child(child)
	return p


static func vbox(sep := 0) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


static func hbox(sep := 0) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


static func margin(child: Control, top := 0, right := 0, bottom := 0, left := 0) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_right", right)
	m.add_theme_constant_override("margin_bottom", bottom)
	m.add_theme_constant_override("margin_left", left)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if child:
		m.add_child(child)
	return m


static func spacer(w := 0.0, h := 0.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func expander() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## A <kbd> keycap: text in a small rounded box.
static func kbd(text: String, settings: LabelSettings, style: StyleBox) -> PanelContainer:
	var p := panel(style, label(text, settings, HORIZONTAL_ALIGNMENT_CENTER))
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


## A line of text with keycaps: parts = ["text", ["KEY"], "more text", ...] (no wrapping).
static func kbd_line(parts: Array, text_ls: LabelSettings, key_ls: LabelSettings, key_style: StyleBox) -> HBoxContainer:
	var row := hbox(0)
	for p in parts:
		if p is Array:
			row.add_child(kbd(str(p[0]), key_ls, key_style))
		else:
			var l := label(str(p), text_ls)
			l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(l)
	return row


## CSS line-height for a label built with ls(..., line_height): wraps it in a margin that trims
## (or pads) half the leading top and bottom, so the box is lines * size * line_height tall
## like the CSS box (matters for the display font, whose fallback has a tall ascent).
static func tight(l: Label) -> MarginContainer:
	var s: LabelSettings = l.label_settings
	var half := s.line_spacing * 0.5
	var m := margin(l, int(floor(half)), 0, int(ceil(half)), 0)
	m.size_flags_horizontal = l.size_flags_horizontal
	return m


## A Label that is as wide as its text up to max_w, and wraps beyond that.
static func fit_label(l: Label, max_w: float) -> void:
	var s: LabelSettings = l.label_settings
	var w := 0.0
	for line in l.text.split("\n"):
		w = maxf(w, s.font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, s.font_size).x)
	l.custom_minimum_size.x = minf(ceilf(w) + 2.0, max_w)


# ---- boxes ----------------------------------------------------------------------------
static func box(bg: Color, pad: Array = [0, 0, 0, 0], radius := 0, border := 0, border_color := Color(0, 0, 0, 0),
		shadow_offset := Vector2.ZERO, shadow_color := Color(0, 0, 0, 0)) -> StyleBox:
	var b = Box.new()
	b.bg = bg
	b.radius = radius
	b.border = border
	b.border_color = border_color
	b.shadow_offset = shadow_offset
	b.shadow_color = shadow_color
	b.set_pad(pad)
	b.rebuild()
	return b


## A box with a coloured left stripe of width w (the stripe sits inside the padding).
static func striped(bg: Color, pad: Array, radius: int, stripe_color: Color, w: int, shadow_offset := Vector2.ZERO, shadow_color := Color(0, 0, 0, 0)) -> StyleBox:
	var b = box(bg, [0, 0, 0, 0], radius, 0, Color(0, 0, 0, 0), shadow_offset, shadow_color)
	b.stripe = w
	b.stripe_color = stripe_color
	b.set_pad(pad)
	b.rebuild()
	return b


static func focus_ring() -> StyleBox:
	var f := StyleBoxFlat.new()
	f.draw_center = false
	f.set_border_width_all(3)
	f.border_color = TICKET
	f.set_corner_radius_all(4)
	f.set_expand_margin_all(5)
	return f


static func empty() -> StyleBox:
	return StyleBoxEmpty.new()


# ---- theme ----------------------------------------------------------------------------
static var _theme: Theme


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = body(500)
	t.default_font_size = 16
	t.set_color("font_color", "Label", PAPER)
	t.set_constant("line_spacing", "Label", 0)
	for type in ["PanelContainer", "Panel"]:
		t.set_stylebox("panel", type, empty())
	# .go buttons (title / game over)
	_go(t, "GoButton", SIREN, PAPER, INK)
	_go(t, "GoAltButton", TICKET, INK, SIREN)
	# #hang and #mvskip: red, upper-case, bold
	_flat_button(t, "HangButton", SIREN, PAPER, [7, 12, 7, 12], 3, spaced(body(700), 1), 16)
	_flat_button(t, "SkipButton", SIREN, PAPER, [9, 16, 9, 16], 3, spaced(body(700), 1), 15)
	# keypad keys
	t.set_type_variation("KeyButton", "Button")
	var kn = box(INK, [0, 0, 0, 0], 8, 0, Color(0, 0, 0, 0), Vector2(0, 3), KEY_SHADOW)
	var kp = kn.copy()
	kp.draw_offset = Vector2(0, 2)
	kp.shadow_offset = Vector2(0, 1)
	kp.content_margin_top = 4
	kp.rebuild()
	for st in ["normal", "hover", "focus"]:
		t.set_stylebox(st, "KeyButton", kn if st != "focus" else empty())
	t.set_stylebox("pressed", "KeyButton", kp)
	t.set_stylebox("hover_pressed", "KeyButton", kp)
	t.set_stylebox("disabled", "KeyButton", kn)
	t.set_font("font", "KeyButton", mono(true))
	t.set_font_size("font_size", "KeyButton", 24)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color", "font_disabled_color"]:
		t.set_color(c, "KeyButton", PAPER)
	# video play/pause
	_flat_button(t, "VideoButton", Color(1, 1, 1, 0.12), PAPER, [6, 12, 6, 12], 3, body(700), 15)
	_theme = t
	return t


static func _go(t: Theme, type: String, bg: Color, fg: Color, sh: Color) -> void:
	t.set_type_variation(type, "Button")
	var n = box(bg, [12, 22, 12, 22], 3, 0, Color(0, 0, 0, 0), Vector2(5, 5), sh)
	var h = n.copy()
	h.draw_offset = Vector2(-1, -1)
	h.shadow_offset = Vector2(6, 6)
	h.rebuild()
	t.set_stylebox("normal", type, n)
	t.set_stylebox("hover", type, h)
	t.set_stylebox("pressed", type, n)
	t.set_stylebox("hover_pressed", type, n)
	t.set_stylebox("disabled", type, n)
	t.set_stylebox("focus", type, focus_ring())
	t.set_font("font", type, disp(22))
	t.set_font_size("font_size", type, 22)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, type, fg)


static func _flat_button(t: Theme, type: String, bg: Color, fg: Color, pad: Array, radius: int, f: Font, size: int) -> void:
	t.set_type_variation(type, "Button")
	var n := box(bg, pad, radius)
	var h := box(bg.lightened(0.08), pad, radius)
	t.set_stylebox("normal", type, n)
	t.set_stylebox("hover", type, h)
	t.set_stylebox("pressed", type, n)
	t.set_stylebox("hover_pressed", type, n)
	t.set_stylebox("disabled", type, n)
	t.set_stylebox("focus", type, focus_ring())
	t.set_font("font", type, f)
	t.set_font_size("font_size", type, size)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, type, fg)


static var _flat := {}



## A cached rounded StyleBoxFlat for drawing.
static func flat(c: Color, r := 0, border := 0, bc := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var k := "%s|%d|%d|%s" % [c.to_html(), r, border, bc.to_html()]
	if _flat.has(k):
		return _flat[k]
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(r)
	s.set_border_width_all(border)
	s.border_color = bc
	s.anti_aliasing_size = 0.7
	_flat[k] = s
	return s


## Draw a string so that a CSS box with this line-height would hold it (centered like CSS).
static func draw_text_line(ci: CanvasItem, f: Font, size: int, text: String, top_left: Vector2, line_h: float, col: Color, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var asc := f.get_ascent(size)
	var desc := f.get_descent(size)
	var base := top_left.y + (line_h - (asc + desc)) * 0.5 + asc
	ci.draw_string(f, Vector2(top_left.x, base), text, align, width, size, col)


# ---- text helpers ---------------------------------------------------------------------
## 1640 -> "1,640" (toLocaleString)
static func commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## Seconds -> "m:ss", rounded up, never negative (engine.js fmt).
static func fmt(sec: float) -> String:
	if is_inf(sec) or is_nan(sec):
		return "0:00"
	var t := maxi(0, ceili(sec))
	return "%d:%02d" % [t / 60, t % 60]
