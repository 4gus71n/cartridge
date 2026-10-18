class_name RoundButton
extends Button
## Circular button with a vector icon (no font-glyph dependency):
## "play", "replay", "stop", "menu", "close". `pulse` draws an expanding
## ring that invites the first tap.

var kind := "play":
	set(v):
		kind = v
		queue_redraw()
var fill := Color("#38d9c0")
var icon_color := Color("#06231f")
var pulse := false
var _t := 0.0


func _init(k: String = "play", side: float = 88.0) -> void:
	kind = k
	custom_minimum_size = Vector2(side, side)
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(delta: float) -> void:
	_t += delta
	if pulse or button_pressed:
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	if pulse:
		for k in 2:
			var ph := fmod(_t * 0.7 + k * 0.5, 1.0)
			draw_arc(c, r * (0.92 + ph * 0.5), 0, TAU, 64, Color(fill, 0.55 * (1.0 - ph)), 4.0, true)
	var f := fill.darkened(0.2) if is_pressed() else fill
	draw_circle(c, r * 0.92, f)
	var s := r * 0.36
	match kind:
		"play":
			var pts := PackedVector2Array([c + Vector2(-s * 0.7, -s), c + Vector2(s * 1.05, 0), c + Vector2(-s * 0.7, s)])
			draw_colored_polygon(pts, icon_color)
		"stop":
			draw_rect(Rect2(c - Vector2(s, s) * 0.8, Vector2(s, s) * 1.6), icon_color)
		"replay":
			draw_arc(c, s * 1.05, deg_to_rad(-60), deg_to_rad(250), 32, icon_color, s * 0.34, true)
			var tip := c + Vector2(cos(deg_to_rad(-60)), sin(deg_to_rad(-60))) * s * 1.05
			var pts2 := PackedVector2Array([tip + Vector2(-s * 0.55, -s * 0.25), tip + Vector2(s * 0.35, -s * 0.5), tip + Vector2(s * 0.12, s * 0.5)])
			draw_colored_polygon(pts2, icon_color)
		"menu":
			for k in 3:
				var y := c.y + (k - 1) * s * 0.62
				draw_line(Vector2(c.x - s * 0.8, y), Vector2(c.x + s * 0.8, y), icon_color, s * 0.24, true)
		"close":
			var d := s * 0.7
			draw_line(c + Vector2(-d, -d), c + Vector2(d, d), icon_color, s * 0.26, true)
			draw_line(c + Vector2(-d, d), c + Vector2(d, -d), icon_color, s * 0.26, true)
