class_name HudBar
extends Control
## Rounded value bar with centred caption (HP / XP).

var value := 1.0
var color := Color("#ff6b5e")
var caption := ""
var font_size := 24


func set_value(v: float, cap: String) -> void:
	value = clampf(v, 0.0, 1.0)
	caption = cap
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#0e0d14")
	bg.set_corner_radius_all(int(size.y / 2))
	draw_style_box(bg, r)
	if value > 0.0:
		var fg := StyleBoxFlat.new()
		fg.bg_color = color
		fg.set_corner_radius_all(int(size.y / 2))
		draw_style_box(fg, Rect2(Vector2.ZERO, Vector2(maxf(size.y, size.x * value), size.y)))
	if caption != "":
		var f := ThemeDB.fallback_font
		var y := (size.y + f.get_ascent(font_size) - f.get_descent(font_size)) / 2.0
		draw_string_outline(f, Vector2(0, y), caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, 5, Color(0, 0, 0, 0.8))
		draw_string(f, Vector2(0, y), caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, Color.WHITE)
