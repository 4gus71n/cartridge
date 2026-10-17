class_name RoadScene
extends Control
## Dusk road-side backdrop: sky gradient, hills, a road with moving lane
## dashes and a sign post. The sign itself is a child SignView on top.

const SKY_TOP := Color("#0c1124")
const SKY_LOW := Color("#3a2747")
const GLOW := Color("#ffb703")
const HILLS := Color("#1a1d33")
const VERGE := Color("#16241f")
const ROAD := Color("#2a2d38")
const LINE := Color("#d9dbe2")
const POLE := Color("#9aa0ab")

var speed := 0.35 ## dash scroll speed (road lengths per second)
var moving := true
var sign_view: SignView
var _t := 0.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	sign_view = SignView.new()
	add_child(sign_view)
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	var r := sign_radius()
	sign_view.size = Vector2(r, r) * 2.0 / sign_view.fill_ratio
	sign_view.position = sign_center() - sign_view.size * 0.5
	sign_view.pivot_offset = sign_view.size * 0.5
	queue_redraw()


func sign_center() -> Vector2:
	return Vector2(size.x * 0.5, size.y * 0.44)


func sign_radius() -> float:
	return minf(size.x * 0.4, size.y * 0.37)


func horizon() -> float:
	return size.y * 0.66


func _process(delta: float) -> void:
	if moving and is_visible_in_tree():
		_t = fmod(_t + delta * speed, 1.0)
		queue_redraw()


func _draw() -> void:
	if size.x < 8.0 or size.y < 8.0:
		return
	var w := size.x
	var h := size.y
	var hy := horizon()
	# sky
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, hy), Vector2(0, hy)]),
		PackedColorArray([SKY_TOP, SKY_TOP, SKY_LOW, SKY_LOW]))
	for i in 5:
		draw_circle(Vector2(w * 0.24, hy), w * (0.45 - i * 0.08), Color(GLOW, 0.035 + i * 0.012), true, -1.0, true)
	for st in [[0.08, 0.1], [0.18, 0.28], [0.86, 0.12], [0.72, 0.06], [0.93, 0.33], [0.3, 0.07], [0.62, 0.2]]:
		draw_circle(Vector2(w * st[0], h * st[1]), 1.6, Color(1, 1, 1, 0.5), true, -1.0, true)
	# hills
	var hills := PackedVector2Array([Vector2(0, hy)])
	for i in 13:
		var x := w * i / 12.0
		hills.append(Vector2(x, hy - h * maxf(0.012, 0.04 + 0.03 * sin(i * 1.7) + 0.02 * sin(i * 0.6 + 1.0))))
	hills.append(Vector2(w, hy))
	draw_colored_polygon(hills, HILLS)
	# ground + road (vanishing point left of centre, post stands on the right verge)
	draw_rect(Rect2(0, hy, w, h - hy), VERGE)
	var vx := w * 0.34
	var bl := Vector2(-w * 0.32, h)
	var br := Vector2(w * 0.5, h)
	var vp := Vector2(vx, hy)
	draw_colored_polygon(PackedVector2Array([vp + Vector2(-2, 0), vp + Vector2(2, 0), br, bl]), ROAD)
	draw_line(vp, br, LINE, 3.0, true)
	draw_line(vp, bl, LINE, 3.0, true)
	var mid_bottom := (bl + br) * 0.5
	for i in 7:
		var a := fmod(i / 7.0 + _t, 1.0)
		var b := minf(a + 0.07, 1.0)
		var ya := hy + (h - hy) * a * a
		var yb := hy + (h - hy) * b * b
		var pa := vp.lerp(mid_bottom, (ya - hy) / (h - hy))
		var pb := vp.lerp(mid_bottom, (yb - hy) / (h - hy))
		draw_line(pa, pb, Color(LINE, 0.85), 2.0 + 10.0 * b, true)
	# sign post
	var c := sign_center()
	var r := sign_radius()
	draw_rect(Rect2(c.x - r * 0.055, c.y, r * 0.11, h - c.y), POLE)
	draw_rect(Rect2(c.x - r * 0.055, c.y, r * 0.03, h - c.y), Color(1, 1, 1, 0.15))
