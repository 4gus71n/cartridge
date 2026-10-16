class_name SignView
extends Control
## Draws one sign centred in its rect. Animations use `scale` around the
## centre, so the vector geometry is only rebuilt when the sign changes.

var sign_id := "":
	set(v):
		sign_id = v
		queue_redraw()
var fill_ratio := 0.94
var shadow := true
var _painter := SignPainter.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(func() -> void:
		pivot_offset = size * 0.5
		queue_redraw())
	pivot_offset = size * 0.5


func radius() -> float:
	return minf(size.x, size.y) * 0.5 * fill_ratio


func _draw() -> void:
	if sign_id == "":
		return
	var c := size * 0.5
	var r := radius()
	if shadow:
		draw_circle(c + Vector2(0, r * 0.06), r * 0.98, Color(0, 0, 0, 0.28), true, -1.0, true)
	_painter.paint(self, sign_id, c, r)
