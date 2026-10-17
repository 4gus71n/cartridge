class_name IconButton
extends Button
## Round button with a vector icon (no font glyph dependency):
## "menu", "plus", "minus", "grow" (chevron up), "shrink" (chevron down).

var kind := "menu":
	set(v):
		kind = v
		queue_redraw()
var icon_color := Color("#eef0f6")
var fill := Color(0.09, 0.11, 0.18, 0.86)


func _init(k: String = "menu", side: float = 88.0) -> void:
	kind = k
	custom_minimum_size = Vector2(side, side)
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) * 0.36
	var bg := fill
	if is_pressed() or button_pressed:
		bg = bg.lightened(0.15)
	draw_circle(c, r + 4.0, Color(0, 0, 0, 0.25))
	draw_circle(c, r, bg)
	draw_arc(c, r, 0, TAU, 40, Color(1, 1, 1, 0.12), 2.0, true)
	var w := 4.0
	var s := r * 0.48
	match kind:
		"menu":
			for dy in [-s * 0.62, 0.0, s * 0.62]:
				draw_line(c + Vector2(-s, dy), c + Vector2(s, dy), icon_color, w, true)
		"plus":
			draw_line(c + Vector2(-s, 0), c + Vector2(s, 0), icon_color, w, true)
			draw_line(c + Vector2(0, -s), c + Vector2(0, s), icon_color, w, true)
		"minus":
			draw_line(c + Vector2(-s, 0), c + Vector2(s, 0), icon_color, w, true)
		"grow":
			draw_polyline(PackedVector2Array([c + Vector2(-s, s * 0.45), c + Vector2(0, -s * 0.45), c + Vector2(s, s * 0.45)]), icon_color, w, true)
		"shrink":
			draw_polyline(PackedVector2Array([c + Vector2(-s, -s * 0.45), c + Vector2(0, s * 0.45), c + Vector2(s, -s * 0.45)]), icon_color, w, true)
