class_name IconButton
extends Button
## Button that draws a simple vector glyph on top of its style box, so we do
## not depend on the default font having arrow / backspace symbols.

enum Kind { BACK, PREV, NEXT, BACKSPACE, HELP, CHECK }

var kind := Kind.BACK
var glyph_color := Color("e8ebf5")


func _init(k := Kind.BACK) -> void:
	kind = k
	focus_mode = Control.FOCUS_NONE


func _draw() -> void:
	var c := size * 0.5
	var s := minf(size.x, size.y) * 0.22
	var w := maxf(3.0, s * 0.28)
	var col := glyph_color
	match kind:
		Kind.BACK, Kind.PREV:
			draw_polyline(PackedVector2Array([c + Vector2(s * 0.45, -s), c + Vector2(-s * 0.45, 0), c + Vector2(s * 0.45, s)]), col, w, true)
		Kind.NEXT:
			draw_polyline(PackedVector2Array([c + Vector2(-s * 0.45, -s), c + Vector2(s * 0.45, 0), c + Vector2(-s * 0.45, s)]), col, w, true)
		Kind.BACKSPACE:
			var h := s * 0.8
			var pts := PackedVector2Array([c + Vector2(-s * 1.3, 0), c + Vector2(-s * 0.6, -h), c + Vector2(s * 1.3, -h),
				c + Vector2(s * 1.3, h), c + Vector2(-s * 0.6, h), c + Vector2(-s * 1.3, 0)])
			draw_polyline(pts, col, w * 0.8, true)
			var x := c + Vector2(s * 0.35, 0)
			var k := h * 0.45
			draw_line(x + Vector2(-k, -k), x + Vector2(k, k), col, w * 0.8, true)
			draw_line(x + Vector2(-k, k), x + Vector2(k, -k), col, w * 0.8, true)
		Kind.HELP:
			# light bulb
			draw_arc(c + Vector2(0, -s * 0.25), s * 0.75, PI * 0.8, PI * 2.2, 24, col, w * 0.8, true)
			draw_line(c + Vector2(-s * 0.4, s * 0.45), c + Vector2(-s * 0.4, s * 0.75), col, w * 0.8, true)
			draw_line(c + Vector2(s * 0.4, s * 0.45), c + Vector2(s * 0.4, s * 0.75), col, w * 0.8, true)
			draw_line(c + Vector2(-s * 0.4, s * 0.75), c + Vector2(s * 0.4, s * 0.75), col, w * 0.8, true)
			draw_line(c + Vector2(-s * 0.25, s * 1.05), c + Vector2(s * 0.25, s * 1.05), col, w * 0.8, true)
		Kind.CHECK:
			draw_polyline(PackedVector2Array([c + Vector2(-s * 0.8, 0), c + Vector2(-s * 0.2, s * 0.6), c + Vector2(s * 0.9, -s * 0.6)]), col, w, true)
