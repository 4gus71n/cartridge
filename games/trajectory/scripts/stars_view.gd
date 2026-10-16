class_name StarsView
extends Control
## Row of 3 stars, `count` of them filled (the font has no ★ glyph).

const ON := Color("#ffd166")
const OFF := Color(1, 1, 1, 0.14)

var count := 0:
	set(v):
		count = v
		queue_redraw()
var star_size := 22.0
var gap := 6.0
var pops: Array = [1.0, 1.0, 1.0]   ## per-star scale (animated by the result screen)


func _init(n := 0, sz := 22.0) -> void:
	count = n
	star_size = sz
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(sz * 6 + gap * 2, sz * 2)


func _draw() -> void:
	var total := star_size * 6 + gap * 2
	var x0 := (size.x - total) / 2.0 + star_size
	for k in 3:
		var c := Vector2(x0 + k * (star_size * 2 + gap), size.y / 2.0)
		var s: float = pops[k]
		draw_colored_polygon(PlotView.star_points(c, star_size * s, star_size * 0.45 * s), ON if k < count else OFF)


## Tween-friendly setter for one star's scale (tween_method passes the value
## first, the bound star index second).
func set_pop(v: float, k: int) -> void:
	pops[k] = v
	queue_redraw()
