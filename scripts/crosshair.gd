extends Control
## The red cross he aims with. It is drawn where `at` says (the mouse) while
## `visible`; main.gd shows it while the right mouse button is held with
## something in his hands, and hides the mouse pointer under it.

const RED := Color(0.93, 0.1, 0.12)
const INK := Color(0.03, 0.0, 0.0)

var at := Vector2.ZERO:        # where on the screen, pixels
	set(value):
		at = value
		queue_redraw()
var loose := 0.0:              # 0 steady to 1: the arms open as he moves
	set(value):
		loose = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	var k := get_viewport_rect().size.y / 900.0        # drawn for a 900-line screen
	var gap := (8.0 + 9.0 * loose) * k
	var arm := 15.0 * k
	var ways := [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
	for way: Vector2 in ways:                  # the ink first, then the red inside it
		draw_line(at + way * (gap - 2.0 * k), at + way * (gap + arm + 2.0 * k), INK, 8.0 * k)
	draw_circle(at, 5.0 * k, INK)
	for way: Vector2 in ways:
		draw_line(at + way * gap, at + way * (gap + arm), RED, 4.0 * k)
	draw_circle(at, 2.8 * k, RED)
