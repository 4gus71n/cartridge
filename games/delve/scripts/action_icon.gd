class_name ActionIcon
extends Control
## Small vector icons for the action bar (drawn in code, no assets).

var kind := "wait"
var color := Color("#e9e4f5")


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) / 2.0
	var c := o + Vector2(s, s) / 2.0
	var w := maxf(3.0, s * 0.08)
	var col := color
	match kind:
		"wait": # hourglass
			var a := s * 0.3
			draw_line(c + Vector2(-a, -a), c + Vector2(a, -a), col, w, true)
			draw_line(c + Vector2(-a, a), c + Vector2(a, a), col, w, true)
			draw_line(c + Vector2(-a * 0.8, -a), c + Vector2(a * 0.8, a), col, w, true)
			draw_line(c + Vector2(a * 0.8, -a), c + Vector2(-a * 0.8, a), col, w, true)
		"search": # magnifier
			draw_arc(c + Vector2(-s * 0.06, -s * 0.06), s * 0.22, 0, TAU, 24, col, w, true)
			draw_line(c + Vector2(s * 0.1, s * 0.1), c + Vector2(s * 0.32, s * 0.32), col, w * 1.3, true)
		"grab": # hand-down arrow into tray
			draw_line(c + Vector2(0, -s * 0.32), c + Vector2(0, s * 0.08), col, w, true)
			draw_line(c + Vector2(-s * 0.15, -s * 0.06), c + Vector2(0, s * 0.1), col, w, true)
			draw_line(c + Vector2(s * 0.15, -s * 0.06), c + Vector2(0, s * 0.1), col, w, true)
			draw_polyline(PackedVector2Array([c + Vector2(-s * 0.32, s * 0.12), c + Vector2(-s * 0.32, s * 0.3), c + Vector2(s * 0.32, s * 0.3), c + Vector2(s * 0.32, s * 0.12)]), col, w, true)
		"stairs":
			var p := PackedVector2Array()
			var st := s * 0.16
			var start := c + Vector2(-s * 0.32, -s * 0.28)
			p.append(start)
			for i in 4:
				p.append(start + Vector2(st * i, st * (i + 1)))
				p.append(start + Vector2(st * (i + 1), st * (i + 1)))
			draw_polyline(p, col, w, true)
		"pack": # satchel
			var r := Rect2(c + Vector2(-s * 0.3, -s * 0.12), Vector2(s * 0.6, s * 0.42))
			var sb := StyleBoxFlat.new()
			sb.draw_center = false
			sb.border_color = col
			sb.set_border_width_all(int(w))
			sb.set_corner_radius_all(int(s * 0.08))
			draw_style_box(sb, r)
			draw_arc(c + Vector2(0, -s * 0.12), s * 0.14, PI, TAU, 16, col, w, true)
			draw_line(c + Vector2(-s * 0.3, s * 0.04), c + Vector2(s * 0.3, s * 0.04), col, w * 0.7, true)
		"map": # folded map
			var p2 := PackedVector2Array([c + Vector2(-s * 0.34, -s * 0.24), c + Vector2(-s * 0.11, -s * 0.32), c + Vector2(s * 0.11, -s * 0.24), c + Vector2(s * 0.34, -s * 0.32), c + Vector2(s * 0.34, s * 0.24), c + Vector2(s * 0.11, s * 0.32), c + Vector2(-s * 0.11, s * 0.24), c + Vector2(-s * 0.34, s * 0.32), c + Vector2(-s * 0.34, -s * 0.24)])
			draw_polyline(p2, col, w, true)
			draw_line(c + Vector2(-s * 0.11, -s * 0.32), c + Vector2(-s * 0.11, s * 0.24), col, w * 0.6, true)
			draw_line(c + Vector2(s * 0.11, -s * 0.24), c + Vector2(s * 0.11, s * 0.32), col, w * 0.6, true)
		"menu":
			for i in 3:
				var y := c.y + (i - 1) * s * 0.2
				draw_line(Vector2(c.x - s * 0.26, y), Vector2(c.x + s * 0.26, y), col, w, true)
