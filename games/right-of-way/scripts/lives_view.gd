class_name LivesView
extends Control
## Row of hearts drawn in code (no glyph dependency): full = life left.

const FULL := Color("#ff4d5a")
const EMPTY := Color(1, 1, 1, 0.14)

var total := 3
var lives := 3:
	set(v):
		if v < lives and is_inside_tree():
			_lost_at = Time.get_ticks_msec()
		lives = v
		queue_redraw()
var _lost_at := -10000


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() - _lost_at < 600:
		queue_redraw()


func _draw() -> void:
	if size.x < 8.0 or size.y < 8.0:
		return
	var s := minf(size.y * 0.62, size.x / (total * 1.3))
	var gap := s * 1.28
	var x0 := size.x * 0.5 - gap * (total - 1) * 0.5
	var flash := clampf(1.0 - (Time.get_ticks_msec() - _lost_at) / 600.0, 0.0, 1.0)
	for i in total:
		var col := FULL if i < lives else EMPTY
		var sc := 1.0
		if i == lives and flash > 0.0:
			col = EMPTY.lerp(Color.WHITE, flash)
			sc = 1.0 + 0.4 * flash
		heart(self, Vector2(x0 + gap * i, size.y * 0.52), s * sc, col)


static func heart(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 48:
		var t := TAU * k / 48.0
		var x := 16.0 * pow(sin(t), 3)
		var y := 13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t)
		pts.append(c + Vector2(x, -y - 2.0) * (s / 34.0))
	ci.draw_colored_polygon(pts, col)
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, col, 1.0, true)
