extends RefCounted
## Small custom-drawn HUD pieces (the bits the web draws with CSS shapes, SVG or canvas).
## `const Wd := preload("res://scripts/ui/hud_widgets.gd")`, then Wd.Arrow.new() etc.

const T := preload("res://scripts/ui/hud_theme.gd")

# ---------------------------------------------------------------------------- case file
## .case .dir b: the 22 px direction arrow (clip-path polygon), rotated.
class Arrow extends Control:
	var ang := 0.0:
		set(v):
			if absf(v - ang) > 0.004:
				ang = v
				queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(22, 22)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var c := Vector2(11, 11)
		var pts := PackedVector2Array([Vector2(11, 0), Vector2(22, 22), Vector2(11, 16.72), Vector2(0, 22)])
		var out := PackedVector2Array()
		for p in pts:
			out.append(c + (p - c).rotated(ang))
		draw_colored_polygon(out, T.INK)
		draw_polyline(out + PackedVector2Array([out[0]]), T.INK, 0.8, true)


## .bar: 5 px progress bar.
class Bar extends Control:
	var frac := 1.0
	var urgent := false
	var bg_color := T.a(T.INK, 0.15)
	var fill_color := T.INK

	func _init() -> void:
		custom_minimum_size = Vector2(0, 5)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_value(f: float, u: bool) -> void:
		if absf(f - frac) > 0.001 or u != urgent:
			frac = f
			urgent = u
			queue_redraw()

	func _draw() -> void:
		draw_style_box(T.flat(bg_color, 3), Rect2(Vector2.ZERO, size))
		var w := size.x * clampf(frac, 0.0, 1.0)
		if w > 0.5:
			draw_style_box(T.flat(T.SIREN if urgent else fill_color, 2 if w > 4.0 else 0), Rect2(0, 0, w, size.y))


## The NEXT block's dashed top border (border-top: 1px dashed rgba(20,32,63,.35)).
class NextBlock extends MarginContainer:
	func _init() -> void:
		add_theme_constant_override("margin_top", 8)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var x := 0.0
		var col := T.a(T.INK, 0.35)
		while x < size.x:
			draw_rect(Rect2(x, 3, minf(3.0, size.x - x), 1), col)
			x += 6.0


# ---------------------------------------------------------------------------- score plate
## #strikes i: 14 px ring, filled when on.
class Strike extends Control:
	var on := false:
		set(v):
			if v != on:
				on = v
				queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(14, 14)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var c := size * 0.5
		if on:
			draw_circle(c, 7.0, T.SIREN, true, -1.0, true)
		else:
			draw_arc(c, 6.0, 0, TAU, 40, T.SIREN, 2.0, true)


# ---------------------------------------------------------------------------- markers
## .mk: a box with one line of display text (line-height 1), drawn by hand so the box is as
## tight as the CSS one whatever the fallback font's ascent/descent are.
class Tag extends Control:
	var text := ""
	var font: Font
	var font_size := 20
	var fg := Color.WHITE
	var style: StyleBox
	var line_h := 1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func setup(t: String, f: Font, fs: int, col: Color, st: StyleBox) -> void:
		if t == text and f == font and fs == font_size and col == fg and st == style:
			return
		text = t
		font = f
		font_size = fs
		fg = col
		style = st
		update_minimum_size()
		size = get_combined_minimum_size()
		queue_redraw()

	func _get_minimum_size() -> Vector2:
		if font == null or style == null:
			return Vector2.ZERO
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		return Vector2(ceilf(w), ceilf(font_size * line_h)) + style.get_minimum_size()

	func _draw() -> void:
		if font == null or style == null:
			return
		draw_style_box(style, Rect2(Vector2.ZERO, size))
		var tl := Vector2(style.get_margin(SIDE_LEFT), style.get_margin(SIDE_TOP))
		T.draw_text_line(self, font, font_size, text, tl, font_size * line_h, fg)


# ---------------------------------------------------------------------------- binoculars
const SHADE_SHADER := """
shader_type canvas_item;
uniform vec2 rect_size = vec2(1600.0, 900.0);
uniform vec2 c1 = vec2(570.0, 450.0);
uniform vec2 c2 = vec2(1030.0, 450.0);
uniform float radius = 324.0;
uniform float soft = 1.5;
uniform vec4 shade : source_color = vec4(0.0157, 0.0235, 0.047, 0.93);
void fragment() {
	vec2 p = UV * rect_size;
	float d = min(distance(p, c1), distance(p, c2)) - radius;
	COLOR = vec4(shade.rgb, shade.a * clamp(d / soft + 0.5, 0.0, 1.0));
}
"""


## #bino: the dark shade with two round holes (the SVG mask), full screen.
class Shade extends ColorRect:
	var _mat: ShaderMaterial

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		color = Color.WHITE
		var sh := Shader.new()
		sh.code = SHADE_SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		material = _mat
		resized.connect(_fit)

	func _fit() -> void:
		var w := size.x
		var h := size.y
		var r := minf(w, h) * 0.36
		var o := r * 0.72
		_mat.set_shader_parameter("rect_size", Vector2(w, h))
		_mat.set_shader_parameter("c1", Vector2(w * 0.5 - o, h * 0.5))
		_mat.set_shader_parameter("c2", Vector2(w * 0.5 + o, h * 0.5))
		_mat.set_shader_parameter("radius", r)


## #reticle: 84 px, the faint circle, the yellow evidence ring and four ticks.
class Reticle extends Control:
	var progress := 0.0:
		set(v):
			v = clampf(v, 0.0, 1.0)
			if absf(v - progress) > 0.0005:
				progress = v
				queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(84, 84)
		size = Vector2(84, 84)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := Vector2(42, 42)
		draw_arc(c, 34, 0, TAU, 96, T.a(T.PAPER, 0.55), 2.0, true)
		if progress > 0.002:
			var a0 := -PI / 2.0
			var a1 := a0 + TAU * progress
			draw_arc(c, 34, a0, a1, maxi(6, int(96 * progress)), T.TICKET, 5.0, true)
			draw_circle(c + Vector2.from_angle(a0) * 34.0, 2.5, T.TICKET, true, -1.0, true)
			draw_circle(c + Vector2.from_angle(a1) * 34.0, 2.5, T.TICKET, true, -1.0, true)
		for seg in [[Vector2(42, 2), Vector2(42, 16)], [Vector2(42, 68), Vector2(42, 82)], [Vector2(2, 42), Vector2(16, 42)], [Vector2(68, 42), Vector2(82, 42)]]:
			draw_line(seg[0], seg[1], T.PAPER, 2.0, true)


# ---------------------------------------------------------------------------- minigame panel
## .track: the rhythm track, 6 pips at (i+1)/7, the moving head.
class Track extends Control:
	var head := 0.0
	var hits := [false, false, false, false, false, false]

	func _init() -> void:
		custom_minimum_size = Vector2(0, 34)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		draw_style_box(T.flat(T.INK, 17), Rect2(0, 0, w, 34))
		var x := w * clampf(head, 0.0, 1.0)
		draw_style_box(T.flat(T.PAPER, 2), Rect2(x - 2.0, 4, 4, 26))
		for i in 6:
			var c := Vector2(w * (i + 1) / 7.0, 17)
			if hits[i]:
				draw_circle(c, 9.0, T.TICKET, true, -1.0, true)
			else:
				draw_arc(c, 7.5, 0, TAU, 40, T.TICKET, 3.0, true)


## .ruler: 1 inch in sixteenths, the green 1/4" band, the needle.
class Ruler extends Control:
	var needle := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(0, 50)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_style_box(T.flat(T.RULER, 2, 2, T.INK), Rect2(Vector2.ZERO, size))
		var r := Rect2(2, 2, size.x - 4, size.y - 4)
		draw_rect(Rect2(r.position.x + r.size.x * 0.21, r.position.y, r.size.x * 0.08, r.size.y), Color(47 / 255.0, 158 / 255.0, 91 / 255.0, 0.35))
		for i in 17:
			var x := r.position.x + r.size.x * i / 16.0
			var h := r.size.y * (0.6 if i % 4 == 0 else (0.4 if i % 2 == 0 else 0.24))
			draw_rect(Rect2(minf(x, r.end.x - 1.0), r.position.y, 1, h), T.INK)
		var f: Font = T.mono(true)
		var labels := ["0", "1/4", "1/2", "3/4", "1"]
		for k in 5:
			var x := r.position.x + r.size.x * k / 4.0
			var tw := f.get_string_size(labels[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			var lx := x - tw * 0.5
			if k == 0:
				lx = x + 2.0
			elif k == 4:
				lx = x - tw - 2.0
			draw_string(f, Vector2(lx, r.end.y - 2.0 - f.get_descent(10)), labels[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, T.INK)
		var nx := r.position.x + r.size.x * clampf(needle, 0.0, 1.0)
		draw_style_box(T.flat(T.GO, 2), Rect2(nx - 2.5, r.position.y, 5, r.size.y))


## .rec .vu: the record level meter (green / yellow / red across the bar's own width).
class Vu extends Control:
	var level := 0.05

	func _init() -> void:
		custom_minimum_size = Vector2(0, 22)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_style_box(T.flat(T.INK, 3), Rect2(Vector2.ZERO, size))
		var sw := size.x * clampf(level, 0.0, 1.0)
		if sw < 1.0:
			return
		draw_rect(Rect2(0, 0, sw * 0.6, size.y), T.GO)
		draw_rect(Rect2(sw * 0.6, 0, sw * 0.25, size.y), T.TICKET)
		draw_rect(Rect2(sw * 0.85, 0, sw * 0.15, size.y), T.SIREN)


# ---------------------------------------------------------------------------- puzzles
## A 58 px wire tile: a dark button that draws its wire segments, turned by `turns` quarter
## turns with the CSS .14 s ease-out rotation. mask bits: N=1 E=2 S=4 W=8 (unturned).
class WireCell extends Button:
	var mask := 0
	var turns := 0
	var powered := false:
		set(v):
			if v != powered:
				powered = v
				queue_redraw()
	var _ang := 0.0
	var _from := 0.0
	var _t := 1.0

	func _init() -> void:
		custom_minimum_size = Vector2(58, 58)
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		add_theme_stylebox_override("normal", T.flat(T.INK, 4))
		add_theme_stylebox_override("hover", T.flat(T.WIRE_HOVER, 4))
		add_theme_stylebox_override("pressed", T.flat(T.WIRE_HOVER, 4))
		add_theme_stylebox_override("hover_pressed", T.flat(T.WIRE_HOVER, 4))
		add_theme_stylebox_override("disabled", T.flat(T.INK, 4))
		add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		set_process(false)

	func set_turns(n: int, animate: bool) -> void:
		turns = n
		if animate:
			_from = _ang
			_t = 0.0
			set_process(true)
		else:
			_ang = turns * PI / 2.0
			_t = 1.0
		queue_redraw()

	func _process(delta: float) -> void:
		_t = minf(1.0, _t + delta / 0.14)
		var e := 1.0 - pow(1.0 - _t, 2.2)
		_ang = lerpf(_from, turns * PI / 2.0, e)
		queue_redraw()
		if _t >= 1.0:
			set_process(false)

	func _draw() -> void:
		var s := size.x / 60.0
		var c := Vector2(30, 30) * s
		var col := T.TICKET if powered else T.WIRE
		for d in [[1, Vector2(30, 4)], [2, Vector2(56, 30)], [4, Vector2(30, 56)], [8, Vector2(4, 30)]]:
			if mask & d[0]:
				var e: Vector2 = c + ((d[1] as Vector2) * s - c).rotated(_ang)
				draw_line(c, e, col, 10.0 * s, true)
				draw_circle(e, 5.0 * s, col, true, -1.0, true)
		draw_circle(c, 6.0 * s, col, true, -1.0, true)


## #livecam .lbl::before: the blinking 8 px dot (1 s, steps(2)).
class LiveDot extends Control:
	var _t := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(8, 8)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _process(delta: float) -> void:
		var was := fmod(_t, 1.0) < 0.5
		_t += delta
		if (fmod(_t, 1.0) < 0.5) != was:
			queue_redraw()

	func _draw() -> void:
		if fmod(_t, 1.0) < 0.5:
			draw_circle(size * 0.5, 4.0, T.PAPER, true, -1.0, true)


## A PanelContainer that acts as a button (for menu options whose text wraps).
class ClickPanel extends PanelContainer:
	signal pressed
	var normal_style: StyleBox
	var hover_style: StyleBox
	var _hover := false

	func _init(n: StyleBox, h: StyleBox) -> void:
		normal_style = n
		hover_style = h
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		add_theme_stylebox_override("panel", n)
		mouse_entered.connect(func():
			_hover = true
			add_theme_stylebox_override("panel", hover_style))
		mouse_exited.connect(func():
			_hover = false
			add_theme_stylebox_override("panel", normal_style))

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
			accept_event()
			pressed.emit()
