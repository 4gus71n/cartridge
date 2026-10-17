class_name TimerBar
extends Control
## Rounded countdown bar: green → amber → red as time runs out.

const TRACK := Color(1, 1, 1, 0.08)
const GREEN := Color("#3ddc84")
const AMBER := Color("#ffb703")
const RED := Color("#ff4d5a")

var ratio := 1.0:
	set(v):
		ratio = clampf(v, 0.0, 1.0)
		queue_redraw()
var frozen := false:
	set(v):
		frozen = v
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func bar_color() -> Color:
	if ratio > 0.5:
		return AMBER.lerp(GREEN, (ratio - 0.5) * 2.0)
	return RED.lerp(AMBER, ratio * 2.0)


func _draw() -> void:
	var rad := size.y * 0.5
	var track := StyleBoxFlat.new()
	track.bg_color = TRACK
	track.set_corner_radius_all(int(rad))
	track.anti_aliasing = true
	draw_style_box(track, Rect2(Vector2.ZERO, size))
	var w := size.x * ratio
	if w < 1.0:
		return
	var fill := StyleBoxFlat.new()
	fill.bg_color = bar_color() if not frozen else Color(0.6, 0.62, 0.7, 0.6)
	fill.set_corner_radius_all(int(minf(rad, w * 0.5)))
	fill.anti_aliasing = true
	draw_style_box(fill, Rect2(0, 0, maxf(w, size.y), size.y))
