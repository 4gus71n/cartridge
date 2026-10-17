class_name PadKey
extends Button
## Number-pad digit (with remaining count) or toolbar key (vector icon +
## caption). Drawn in code so it needs no image assets.

const TEXT := Color("#eef1ff")
const MUTED := Color("#8d93b4")
const ACCENT := Color("#ffa53d")

var digit := 0 ## 1..9 for a number key, 0 for a tool key
var remaining := 9:
	set(v):
		remaining = v
		queue_redraw()
var icon_name := ""
var caption := ""
var badge := "" ## small text in the top-right corner (e.g. hints used)
var active := false: ## toggle look (notes mode, mistake check)
	set(v):
		active = v
		queue_redraw()
var notes_mode := false: ## number keys show pencil-style digits in notes mode
	set(v):
		notes_mode = v
		queue_redraw()


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	text = ""


func _draw() -> void:
	var font := get_theme_default_font()
	var r := Rect2(Vector2.ZERO, size)
	if active:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(ACCENT, 0.22)
		sb.border_color = ACCENT
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(18)
		sb.anti_aliasing = true
		draw_style_box(sb, r)
	if digit > 0:
		var done := remaining <= 0
		var col := ACCENT if notes_mode else TEXT
		if done:
			col = Color(MUTED, 0.45)
		var fs := 50 if not notes_mode else 40
		var asc := font.get_ascent(fs)
		draw_string(font, Vector2(0, size.y * 0.47 + asc * 0.36), str(digit), HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, col)
		var sub := "" if done else str(remaining)
		draw_string(font, Vector2(0, size.y - 14), sub, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, MUTED)
		return
	var c := Vector2(size.x / 2.0, size.y * 0.38)
	var col2 := ACCENT if active else TEXT
	_icon(c, col2)
	draw_string(font, Vector2(0, size.y - 14), caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, ACCENT if active else MUTED)
	if badge != "":
		var bc := Vector2(size.x / 2.0 + 26, size.y * 0.38 - 20)
		draw_circle(bc, 15, ACCENT)
		draw_string(font, bc + Vector2(-20, 7), badge, HORIZONTAL_ALIGNMENT_CENTER, 40, 20, Color("#1a1205"))


func _icon(c: Vector2, col: Color) -> void:
	match icon_name:
		"undo":
			draw_arc(c + Vector2(2, 2), 14, PI * 1.1, PI * 2.35, 18, col, 4.0, true)
			var tip := c + Vector2(2, 2) + Vector2.from_angle(PI * 1.1) * 14
			draw_colored_polygon(PackedVector2Array([tip + Vector2(-8, -4), tip + Vector2(6, -6), tip + Vector2(0, 8)]), col)
		"erase":
			var pts := PackedVector2Array([c + Vector2(-16, 6), c + Vector2(2, -12), c + Vector2(14, 0), c + Vector2(-4, 18), c + Vector2(-16, 6)])
			draw_polyline(pts, col, 4.0, true)
			draw_line(c + Vector2(-7, -3), c + Vector2(5, 9), col, 4.0, true)
			draw_line(c + Vector2(-4, 18), c + Vector2(16, 18), col, 3.0, true)
		"notes":
			draw_line(c + Vector2(-12, 14), c + Vector2(10, -10), col, 6.0, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-16, 18), c + Vector2(-14, 10), c + Vector2(-9, 16)]), col)
			draw_line(c + Vector2(8, -12), c + Vector2(12, -16), col, 6.0, true)
		"hint":
			draw_arc(c + Vector2(0, -4), 12, PI * 0.75, PI * 2.25, 20, col, 4.0, true)
			draw_line(c + Vector2(-6, 6), c + Vector2(-5, 12), col, 4.0, true)
			draw_line(c + Vector2(6, 6), c + Vector2(5, 12), col, 4.0, true)
			draw_line(c + Vector2(-6, 14), c + Vector2(6, 14), col, 3.0, true)
			draw_line(c + Vector2(-4, 19), c + Vector2(4, 19), col, 3.0, true)
		"check":
			draw_arc(c, 17, 0, TAU, 28, col, 3.0, true)
			draw_polyline(PackedVector2Array([c + Vector2(-8, 0), c + Vector2(-2, 7), c + Vector2(9, -7)]), col, 4.0, true)
		"back":
			draw_polyline(PackedVector2Array([c + Vector2(6, -14), c + Vector2(-6, 0), c + Vector2(6, 14)]), col, 5.0, true)
