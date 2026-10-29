extends Control
## #mini: the map of the block (hud.js drawMini), redrawn by the HUD every 0.15 s while live.
## x runs left to right (-33..46), z top to bottom (-8..19): houses at the top, street below.

const T := preload("res://scripts/ui/hud_theme.gd")
const St := preload("res://scripts/ui/hud_state.gd")


func _init() -> void:
	custom_minimum_size = Vector2(320, 64)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func _x(x: float) -> float:
	return 5.0 + (x + 33.0) / 79.0 * (size.x - 10.0)


func _z(z: float) -> float:
	return 3.0 + (z + 8.0) / 27.0 * (size.y - 6.0)


func _band(z0: float, z1: float, c: Color) -> void:
	draw_rect(Rect2(0, _z(z0), size.x, _z(z1) - _z(z0)), c)


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(0, 0, w, h), T.INK)
	_band(-8, -7, Color("#3a3f55"))
	_band(-7, -3.2, Color("#4d6a3a"))
	_band(-3.2, 0, Color("#8a8679"))
	_band(0, 13, Color("#2b2c33"))
	_band(13, 19, Color("#8a8679"))
	draw_rect(Rect2(_x(31.5), _z(-8), _x(40.5) - _x(31.5), _z(-6.2) - _z(-8)), T.COP)
	var f: Font = T.mono(true)
	var asc := f.get_ascent(9)
	draw_string(f, Vector2(_x(35), _z(-7.9) + asc), "P9", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, T.PAPER)
	draw_string(f, Vector2(_x(26.4), _z(-7.9) + asc), "BANK", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, T.PAPER)
	for ph in St.phones():
		draw_rect(Rect2(_x(ph.x) - 2.5, _z(ph.y) - 2.5, 5, 5), T.BLUE_DOT)
	var md = St.xz(St.gconst("MAILDROP", [5.9, -3.0]))
	if md != null:
		draw_circle(Vector2(_x(md.x), _z(md.y)), 2.6, T.BLUE_DOT, true, -1.0, true)
	for c in St.crimes():
		if not St.active(c) or St.field(c, "handling", false):
			continue
		var k := St.kind(St.cur(c))
		var t := St.mark(c)
		var col := T.BLUE_DOT if St.field(c, "dispatched", false) else (T.RED if (k == "spy" or k == "tail") else T.TICKET)
		var r := 3.0 if St.field(c, "id", "") == "gary" else 4.2
		var p := Vector2(_x(t.x), _z(t.z))
		draw_circle(p, r, col, true, -1.0, true)
		draw_arc(p, r, 0, TAU, 24, T.INK, 1.0, true)
	var car = St.car_xz()
	if car != null:
		draw_rect(Rect2(_x(car.x) - 5, _z(car.y) - 2.5, 10, 5), T.PAPER)
	var dan = St.dan()
	if dan != null and St.field(dan, "escort") != null and St.field(dan, "escort") != false and str(St.field(dan, "escort")) != "":
		var dp = St.xz(dan)
		if dp != null:
			draw_circle(Vector2(_x(dp.x), _z(dp.y)), 3.0, T.COP, true, -1.0, true)
	var pl = St.gv("P")
	var pp = St.xz(pl)
	if pp != null:
		var yaw := float(St.field(pl, "yaw", 0.0))
		var px := _x(pp.x)
		var pz := _z(pp.y)
		var fx := sin(yaw)
		var fz := cos(yaw)
		var tri := PackedVector2Array([
			Vector2(px + fx * 7, pz + fz * 7),
			Vector2(px - fz * 4 - fx * 3, pz + fx * 4 - fz * 3),
			Vector2(px + fz * 4 - fx * 3, pz - fx * 4 - fz * 3)])
		draw_colored_polygon(tri, T.TICKET)
		draw_polyline(tri + PackedVector2Array([tri[0]]), T.INK, 1.0, true)
