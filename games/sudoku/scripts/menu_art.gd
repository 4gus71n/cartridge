class_name MenuArt
extends Control
## Decorative 3x3 sudoku box for the menu, with a softly pulsing cell.

const DIGITS := [5, 0, 3, 0, 7, 0, 9, 0, 1]
const NOTES := [0, 0x14, 0, 0x42, 0, 0x300, 0, 0x88, 0]
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var cs := minf(size.y / 3.0, 96.0)
	var side := cs * 3.0
	var o := Vector2((size.x - side) / 2.0, (size.y - side) / 2.0)
	var font := get_theme_default_font()
	var sb := StyleBoxFlat.new()
	sb.bg_color = BoardView.PANEL
	sb.border_color = BoardView.THICK
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(14)
	sb.anti_aliasing = true
	draw_style_box(sb, Rect2(o - Vector2(3, 3), Vector2(side + 6, side + 6)))
	var pulse := 0.3 + 0.15 * sin(_t * 2.5)
	draw_rect(Rect2(o + Vector2(1, 1) * cs, Vector2(cs, cs)).grow(-2), Color(BoardView.ACCENT, pulse))
	for k in [1, 2]:
		draw_line(o + Vector2(k * cs, 0), o + Vector2(k * cs, side), BoardView.LINE, 2.0)
		draw_line(o + Vector2(0, k * cs), o + Vector2(side, k * cs), BoardView.LINE, 2.0)
	for i in 9:
		var r := Rect2(o + Vector2(i % 3, i / 3) * cs, Vector2(cs, cs))
		if DIGITS[i] > 0:
			var col := BoardView.ENTRY if i == 4 else BoardView.TEXT
			var fs := int(cs * 0.6)
			draw_string(font, Vector2(r.position.x, r.position.y + cs * 0.5 + font.get_ascent(fs) * 0.36), str(DIGITS[i]), HORIZONTAL_ALIGNMENT_CENTER, cs, fs, col)
		else:
			var sub := cs / 3.0
			for d in range(1, 10):
				if NOTES[i] & (1 << d):
					var p := r.position + Vector2((d - 1) % 3, (d - 1) / 3) * sub
					var fs2 := int(cs * 0.26)
					draw_string(font, Vector2(p.x, p.y + sub * 0.5 + font.get_ascent(fs2) * 0.36), str(d), HORIZONTAL_ALIGNMENT_CENTER, sub, fs2, BoardView.MUTED)
