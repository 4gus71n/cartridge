class_name IconButton
extends Button
## Button with a vector icon drawn in code (the default font has no ⌫ / ☰
## glyphs): "back" (chevron), "info" (i in a circle), "backspace".

var kind := "back"
var icon_color := Color("#e6e9f2")


func _init(k := "back") -> void:
	kind = k
	custom_minimum_size = Vector2(88, 88)
	focus_mode = Control.FOCUS_NONE


func _draw() -> void:
	var c := size / 2.0
	var col := icon_color if not disabled else Color(icon_color, 0.35)
	match kind:
		"back":
			draw_polyline(PackedVector2Array([c + Vector2(8, -16), c + Vector2(-8, 0), c + Vector2(8, 16)]), col,
				5.0, true)
		"info":
			draw_arc(c, 20, 0, TAU, 40, col, 3.5, true)
			draw_circle(c + Vector2(0, -9), 3.0, col)
			draw_line(c + Vector2(0, -2), c + Vector2(0, 11), col, 4.5, true)
		"backspace":
			var pts := PackedVector2Array([c + Vector2(-26, 0), c + Vector2(-12, -16), c + Vector2(24, -16),
				c + Vector2(24, 16), c + Vector2(-12, 16), c + Vector2(-26, 0)])
			draw_polyline(pts, col, 3.5, true)
			draw_line(c + Vector2(-3, -7), c + Vector2(11, 7), col, 3.5, true)
			draw_line(c + Vector2(11, -7), c + Vector2(-3, 7), col, 3.5, true)
