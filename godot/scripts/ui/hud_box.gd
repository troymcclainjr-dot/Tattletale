@tool
extends StyleBox
## A StyleBoxFlat look plus what the CSS uses everywhere and StyleBoxFlat can't do exactly:
## a hard drop shadow (box-shadow: Xpx Ypx 0 color), a coloured left stripe (.case::before,
## border-left), a draw offset (hover lift / pressed key) and a dashed top border.
## Built by hud_theme.gd box() / striped(); call rebuild() after changing fields.

@export var bg := Color(0, 0, 0, 0)
@export var border_color := Color(0, 0, 0, 0)
@export var border := 0
@export var radius := 0
@export var shadow_color := Color(0, 0, 0, 0)
@export var shadow_offset := Vector2.ZERO
@export var stripe_color := Color(0, 0, 0, 0)
@export var stripe := 0
@export var draw_offset := Vector2.ZERO
@export var dashed_top := Color(0, 0, 0, 0)

var _main: StyleBoxFlat
var _shadow: StyleBoxFlat
var _stripe: StyleBoxFlat


## pad = [top, right, bottom, left] like CSS padding (the border is added on top of it).
func set_pad(pad: Array) -> void:
	var p := [0.0, 0.0, 0.0, 0.0]
	match pad.size():
		1:
			p = [pad[0], pad[0], pad[0], pad[0]]
		2:
			p = [pad[0], pad[1], pad[0], pad[1]]
		3:
			p = [pad[0], pad[1], pad[2], pad[1]]
		4:
			p = pad
	content_margin_top = float(p[0]) + border
	content_margin_right = float(p[1]) + border
	content_margin_bottom = float(p[2]) + border
	content_margin_left = float(p[3]) + maxi(border, stripe)


func copy() -> StyleBox:
	var b = duplicate()
	b.rebuild()
	return b


func rebuild() -> void:
	_main = StyleBoxFlat.new()
	_main.bg_color = bg
	_main.draw_center = bg.a > 0.0
	_main.set_corner_radius_all(radius)
	_main.set_border_width_all(border)
	_main.border_color = border_color
	_main.anti_aliasing_size = 0.7
	_shadow = null
	if shadow_color.a > 0.0:
		_shadow = StyleBoxFlat.new()
		_shadow.bg_color = shadow_color
		_shadow.set_corner_radius_all(radius)
		_shadow.anti_aliasing_size = 0.7
	_stripe = null
	if stripe > 0 and stripe_color.a > 0.0:
		_stripe = StyleBoxFlat.new()
		_stripe.bg_color = stripe_color
		_stripe.corner_radius_top_left = radius
		_stripe.corner_radius_bottom_left = radius
		_stripe.anti_aliasing_size = 0.7
	emit_changed()


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if _main == null:
		rebuild()
	var r := Rect2(rect.position + draw_offset, rect.size)
	if _shadow:
		_shadow.draw(to_canvas_item, Rect2(r.position + shadow_offset, r.size))
	_main.draw(to_canvas_item, r)
	if _stripe:
		_stripe.draw(to_canvas_item, Rect2(r.position, Vector2(stripe, r.size.y)))
	if dashed_top.a > 0.0:
		var x := r.position.x
		while x < r.end.x:
			RenderingServer.canvas_item_add_rect(to_canvas_item, Rect2(x, r.position.y, minf(6.0, r.end.x - x), 2.0), dashed_top)
			x += 10.0
