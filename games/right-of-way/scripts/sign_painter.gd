class_name SignPainter
extends RefCounted
## Draws every sign from vector primitives, Vienna Convention style
## (Europe / South America). One routine per sign: `_s_<id>()`.
##
## Coordinates are normalised: the sign spans [-1, 1] around `c`, scaled by
## `r` pixels. Pictograms are authored in their own [-1, 1] box and placed
## with push()/pop(). `ci` is duck-typed (a CanvasItem, or a recorder in the
## headless tests) so every routine can be exercised without a renderer.

const RED := Color("#d8262f")
const BLUE := Color("#1f5cb8")
const YELLOW := Color("#f7c31c")
const WHITE := Color("#fbfaf6")
const INK := Color("#16171b")
const GREY := Color("#8e939c")
const LIGHT_GREEN := Color("#29b05e")
const LIGHT_AMBER := Color("#f6a623")
const LIGHT_RED := Color("#e53935")
const EDGE := Color(0, 0, 0, 0.35)

static var _font: FontVariation

var ci
var c := Vector2.ZERO
var r := 100.0
var o := Vector2.ZERO
var s := 1.0
var _stack: Array = []


## Paints sign `id` centred on `center` with half-size `radius` pixels.
func paint(target, id: String, center: Vector2, radius: float) -> void:
	ci = target
	c = center
	r = radius
	o = Vector2.ZERO
	s = 1.0
	_stack.clear()
	var m := "_s_" + id
	if has_method(m):
		call(m)


static func has_routine(id: String) -> bool:
	return SignPainter.new().has_method("_s_" + id)


static func font() -> Font:
	if _font == null:
		_font = FontVariation.new()
		_font.base_font = ThemeDB.fallback_font
		_font.variation_embolden = 0.9
	return _font


# --- coordinate frame -----------------------------------------------------

func push(ox: float, oy: float, sc: float) -> void:
	_stack.append([o, s])
	o = o + Vector2(ox, oy) * s
	s *= sc


func pop() -> void:
	var top: Array = _stack.pop_back()
	o = top[0]
	s = top[1]


func P(x: float, y: float) -> Vector2:
	return c + (o + Vector2(x, y) * s) * r


func L(length: float) -> float:
	return length * s * r


func _pix(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, pts.size() - 1, 2):
		out.append(P(pts[i], pts[i + 1]))
	return out


# --- primitives -------------------------------------------------------------

## Filled polygon in pixel space with an antialiased rim (polygons have no AA).
func poly_px(px: PackedVector2Array, col: Color) -> void:
	if px.size() < 3:
		return
	ci.draw_colored_polygon(px, col)
	var closed := px.duplicate()
	closed.append(px[0])
	ci.draw_polyline(closed, col, 1.0, true)


func fill(pts: Array, col: Color) -> void:
	poly_px(_pix(pts), col)


func rect(x0: float, y0: float, x1: float, y1: float, col: Color) -> void:
	fill([x0, y0, x1, y0, x1, y1, x0, y1], col)


func rrect(x0: float, y0: float, x1: float, y1: float, rad: float, col: Color) -> void:
	poly_px(rounded(_pix([x0, y0, x1, y0, x1, y1, x0, y1]), L(rad)), col)


func disc(x: float, y: float, rad: float, col: Color) -> void:
	ci.draw_circle(P(x, y), L(rad), col, true, -1.0, true)


func ring(x: float, y: float, rad: float, w: float, col: Color) -> void:
	ci.draw_arc(P(x, y), L(rad), 0.0, TAU, 96, col, L(w), true)


## Thick polyline with round caps and joins.
func line(pts: Array, w: float, col: Color, caps := true) -> void:
	var px := _pix(pts)
	ci.draw_polyline(px, col, L(w), true)
	for i in px.size():
		if caps or (i > 0 and i < px.size() - 1):
			ci.draw_circle(px[i], L(w) * 0.5, col, true, -1.0, true)


## Arrow along `pts` (flat list, normalised) whose last point is the tip.
func arrow(pts: Array, w: float, head_len: float, head_w: float, col: Color) -> void:
	var n := pts.size()
	var tip := Vector2(pts[n - 2], pts[n - 1])
	var prev := Vector2(pts[n - 4], pts[n - 3])
	var dir := (tip - prev).normalized()
	var base := tip - dir * head_len
	var shaft: Array = pts.slice(0, n - 2)
	shaft.append_array([base.x + dir.x * 0.02, base.y + dir.y * 0.02])
	line(shaft, w, col, false)
	var nrm := Vector2(-dir.y, dir.x) * head_w
	fill([base.x + nrm.x, base.y + nrm.y, tip.x, tip.y, base.x - nrm.x, base.y - nrm.y], col)


## Points of an arc (degrees, screen space: 0 = right, 90 = down).
func arc_pts(cx: float, cy: float, rad: float, a0: float, a1: float, steps := 18) -> Array:
	var out := []
	for i in steps + 1:
		var a := deg_to_rad(lerpf(a0, a1, float(i) / steps))
		out.append_array([cx + cos(a) * rad, cy + sin(a) * rad])
	return out


## Centred text; `h` is the cap height in normalised units.
func text(t: String, x: float, y: float, h: float, col: Color, squeeze := 1.0) -> void:
	var f := font()
	var fs := maxi(1, int(L(h) / 0.72))
	var wpx := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := P(x, y)
	if squeeze != 1.0:
		ci.draw_set_transform(pos, 0.0, Vector2(squeeze, 1.0))
		ci.draw_string(f, Vector2(-wpx * 0.5, L(h) * 0.5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		ci.draw_string(f, pos + Vector2(-wpx * 0.5, L(h) * 0.5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Rounds the corners of a convex pixel polygon by `rad_px`.
static func rounded(px: PackedVector2Array, rad_px: float) -> PackedVector2Array:
	var inner := Geometry2D.offset_polygon(px, -rad_px, Geometry2D.JOIN_MITER)
	if inner.is_empty():
		return px
	var outer := Geometry2D.offset_polygon(inner[0], rad_px, Geometry2D.JOIN_ROUND)
	return outer[0] if not outer.is_empty() else px


static func shrink(px: PackedVector2Array, d_px: float) -> PackedVector2Array:
	var res := Geometry2D.offset_polygon(px, -d_px, Geometry2D.JOIN_ROUND)
	return res[0] if not res.is_empty() else px


## Diagonal "end of restriction" stripes (bottom-left to top-right).
func end_stripes(count: int, gap: float, half: float, w: float, col: Color) -> void:
	for i in count:
		var d := (i - (count - 1) * 0.5) * gap
		var t := sqrt(maxf(half * half - d * d, 0.0))
		var n := Vector2(0.7071, 0.7071) * d
		var dir := Vector2(0.7071, -0.7071)
		var a := n - dir * t
		var b := n + dir * t
		line([a.x, a.y, b.x, b.y], w, col, false)


# --- sign bodies ------------------------------------------------------------

func base_prohibition(fill_col := WHITE) -> void:
	disc(0, 0, 1.0, WHITE)
	ring(0, 0, 0.995, 0.01, EDGE)
	disc(0, 0, 0.955, RED)
	disc(0, 0, 0.74, fill_col)


func slash(col := RED) -> void:
	line([-0.53, -0.53, 0.53, 0.53], 0.13, col, false)


func base_blue_disc() -> void:
	disc(0, 0, 1.0, WHITE)
	ring(0, 0, 0.995, 0.01, EDGE)
	disc(0, 0, 0.95, BLUE)


func base_blue_square() -> void:
	var outer := rounded(_pix([-0.93, -0.93, 0.93, -0.93, 0.93, 0.93, -0.93, 0.93]), L(0.16))
	poly_px(outer, WHITE)
	poly_px(shrink(outer, L(0.05)), BLUE)


func base_warning() -> void:
	var outer := rounded(_pix([0, -0.98, 1.0, 0.75, -1.0, 0.75]), L(0.13))
	poly_px(outer, WHITE)
	poly_px(shrink(outer, L(0.035)), RED)
	poly_px(shrink(outer, L(0.2)), WHITE)


## Standard pictogram frame inside a warning triangle.
func warn_frame(sc := 0.34) -> void:
	push(0, 0.22, sc)


func base_end_sign() -> void:
	disc(0, 0, 1.0, WHITE)
	ring(0, 0, 0.97, 0.035, INK)


# --- reusable pictograms (local [-1, 1] box) --------------------------------

func walker(col: Color, stride := 1.0) -> void:
	disc(0.1, -0.8, 0.18, col)
	line([0.05, -0.52, -0.03, 0.06], 0.3, col)
	line([0.0, -0.45, -0.24 * stride, -0.2, -0.36 * stride, 0.08], 0.13, col)
	line([0.08, -0.45, 0.28 * stride, -0.22, 0.42 * stride, 0.0], 0.13, col)
	line([-0.05, 0.06, -0.24 * stride, 0.46, -0.44 * stride, 0.86], 0.17, col)
	line([0.0, 0.06, 0.2 * stride, 0.46, 0.24 * stride, 0.9], 0.17, col)
	line([0.24 * stride, 0.9, 0.4 * stride, 0.9], 0.13, col)


func zebra(col: Color, y: float, w := 0.95) -> void:
	for i in 5:
		var x := -w + i * (2.0 * w / 4.6)
		fill([x, y, x + 0.24, y, x + 0.18, y + 0.14, x - 0.06, y + 0.14], col)


func bicycle(col: Color) -> void:
	ring(-0.55, 0.32, 0.36, 0.09, col)
	ring(0.55, 0.32, 0.36, 0.09, col)
	line([-0.55, 0.32, -0.08, 0.32, 0.36, -0.18, -0.2, -0.18, -0.55, 0.32], 0.09, col)
	line([-0.08, 0.32, -0.26, -0.36], 0.09, col)
	line([-0.4, -0.38, -0.12, -0.38], 0.11, col)
	line([0.55, 0.32, 0.3, -0.42, 0.48, -0.46], 0.09, col)


func car_rear(col: Color, bg: Color) -> void:
	fill([-0.38, -0.05, -0.27, -0.42, 0.27, -0.42, 0.38, -0.05], col)
	fill([-0.29, -0.09, -0.21, -0.35, 0.21, -0.35, 0.29, -0.09], bg)
	rrect(-0.52, -0.08, 0.52, 0.38, 0.1, col)
	rrect(-0.48, 0.3, -0.3, 0.58, 0.04, col)
	rrect(0.3, 0.3, 0.48, 0.58, 0.04, col)
	disc(-0.36, 0.1, 0.07, bg)
	disc(0.36, 0.1, 0.07, bg)


func car_side(col: Color, bg: Color) -> void:
	fill([-0.92, 0.0, -0.86, -0.17, -0.46, -0.24, -0.26, -0.5, 0.3, -0.5, 0.52, -0.22,
		0.86, -0.14, 0.92, 0.02, 0.92, 0.2, -0.92, 0.2], col)
	fill([-0.36, -0.24, -0.2, -0.42, -0.01, -0.42, -0.01, -0.24], bg)
	fill([0.06, -0.24, 0.06, -0.42, 0.26, -0.42, 0.42, -0.24], bg)
	disc(-0.5, 0.22, 0.21, col)
	disc(0.5, 0.22, 0.21, col)
	disc(-0.5, 0.22, 0.08, bg)
	disc(0.5, 0.22, 0.08, bg)


func truck(col: Color, bg: Color) -> void:
	rrect(-0.95, -0.6, 0.3, 0.22, 0.04, col)
	fill([0.36, 0.22, 0.36, -0.4, 0.68, -0.4, 0.95, -0.06, 0.95, 0.22], col)
	fill([0.45, -0.31, 0.64, -0.31, 0.83, -0.1, 0.45, -0.1], bg)
	for wx in [-0.62, -0.18, 0.64]:
		disc(wx, 0.34, 0.2, col)
		disc(wx, 0.34, 0.07, bg)


func round_arrows(col: Color, rad := 0.56, w := 0.16) -> void:
	# Three arrows circulating anticlockwise (as seen from above, keep-right traffic).
	for k in 3:
		var a0 := 90.0 + k * 120.0 - 10.0
		var a1 := a0 - 72.0
		var pts := arc_pts(0, 0, rad, a0, a1, 14)
		var ea := deg_to_rad(a1)
		var tangent := Vector2(sin(ea), -cos(ea))
		var end := Vector2(pts[pts.size() - 2], pts[pts.size() - 1])
		var tip := end + tangent * 0.34
		pts.append_array([tip.x, tip.y])
		arrow(pts, w, 0.34, 0.27, col)


func up_arrow(col: Color, x := 0.0, scale := 1.0) -> void:
	push(x, 0, scale)
	arrow([0, 0.85, 0, -0.85], 0.26, 0.6, 0.48, col)
	pop()


# --- priority ---------------------------------------------------------------

func _s_stop() -> void:
	var pts := []
	for k in 8:
		var a := deg_to_rad(22.5 + 45.0 * k)
		pts.append_array([cos(a) * 1.0, sin(a) * 1.0])
	var outer := rounded(_pix(pts), L(0.08))
	poly_px(outer, WHITE)
	poly_px(shrink(outer, L(0.06)), RED)
	text("STOP", 0, 0.02, 0.44, WHITE, 0.92)


func _s_give_way() -> void:
	var outer := rounded(_pix([-1.0, -0.8, 1.0, -0.8, 0.0, 0.94]), L(0.13))
	poly_px(outer, WHITE)
	poly_px(shrink(outer, L(0.035)), RED)
	poly_px(shrink(outer, L(0.22)), WHITE)


func _diamond() -> void:
	var outer := rounded(_pix([0, -1.0, 1.0, 0, 0, 1.0, -1.0, 0]), L(0.07))
	poly_px(outer, INK)
	poly_px(shrink(outer, L(0.025)), WHITE)
	poly_px(rounded(_pix([0, -0.6, 0.6, 0, 0, 0.6, -0.6, 0]), L(0.03)), YELLOW)


func _s_priority_road() -> void:
	_diamond()


func _s_end_priority() -> void:
	_diamond()
	end_stripes(5, 0.075, 0.62, 0.035, INK)


func _s_yield_oncoming() -> void:
	base_prohibition()
	push(-0.24, 0, 0.62)
	arrow([0, -0.8, 0, 0.8], 0.17, 0.42, 0.3, INK)
	pop()
	push(0.24, 0, 0.62)
	arrow([0, 0.8, 0, -0.8], 0.17, 0.42, 0.3, RED)
	pop()


func _s_priority_over_oncoming() -> void:
	base_blue_square()
	push(-0.25, 0, 0.66)
	arrow([0, -0.8, 0, 0.8], 0.17, 0.42, 0.3, RED)
	pop()
	push(0.25, 0, 0.66)
	arrow([0, 0.8, 0, -0.8], 0.17, 0.42, 0.3, WHITE)
	pop()


# --- prohibition --------------------------------------------------------------

func _s_no_entry() -> void:
	disc(0, 0, 1.0, WHITE)
	ring(0, 0, 0.995, 0.01, EDGE)
	disc(0, 0, 0.955, RED)
	rect(-0.66, -0.15, 0.66, 0.15, WHITE)


func _s_road_closed() -> void:
	base_prohibition()


func _speed(n: String) -> void:
	base_prohibition()
	text(n, 0, 0.0, 0.62, INK, 0.86)


func _s_speed_30() -> void:
	_speed("30")


func _s_speed_60() -> void:
	_speed("60")


func _s_speed_90() -> void:
	_speed("90")


func _s_end_speed_60() -> void:
	base_end_sign()
	text("60", 0, 0.0, 0.62, GREY, 0.86)
	end_stripes(5, 0.07, 0.9, 0.03, INK)


func _s_no_overtaking() -> void:
	base_prohibition()
	push(-0.3, 0.02, 0.5)
	car_rear(RED, WHITE)
	pop()
	push(0.3, 0.02, 0.5)
	car_rear(INK, WHITE)
	pop()


func _s_end_no_overtaking() -> void:
	base_end_sign()
	push(-0.3, 0.02, 0.5)
	car_rear(GREY, WHITE)
	pop()
	push(0.3, 0.02, 0.5)
	car_rear(GREY, WHITE)
	pop()
	end_stripes(5, 0.07, 0.9, 0.03, INK)


func _turn_arrow(col: Color, dir: float) -> void:
	# Arrow coming from below and turning towards `dir` (+1 right, -1 left).
	var pts := [-0.22 * dir, 0.85, -0.22 * dir, 0.05]
	var arc := arc_pts(0.2 * dir, 0.05, 0.42, 180.0 if dir > 0 else 0.0, 270.0 if dir > 0 else -90.0, 10)
	pts.append_array(arc)
	pts.append_array([0.75 * dir, -0.37])
	arrow(pts, 0.2, 0.42, 0.36, col)


func _s_no_left_turn() -> void:
	base_prohibition()
	push(0.05, 0.04, 0.6)
	_turn_arrow(INK, -1.0)
	pop()
	slash()


func _s_no_right_turn() -> void:
	base_prohibition()
	push(-0.05, 0.04, 0.6)
	_turn_arrow(INK, 1.0)
	pop()
	slash()


func _s_no_u_turn() -> void:
	base_prohibition()
	push(0, 0.04, 0.6)
	var pts := [0.32, 0.85, 0.32, -0.15]
	pts.append_array(arc_pts(0.0, -0.15, 0.32, 0.0, -180.0, 14))
	pts.append_array([-0.32, 0.25, -0.32, 0.7])
	arrow(pts, 0.2, 0.42, 0.34, INK)
	pop()
	slash()


func _blue_ban(cross: bool) -> void:
	disc(0, 0, 1.0, WHITE)
	ring(0, 0, 0.995, 0.01, EDGE)
	disc(0, 0, 0.955, RED)
	disc(0, 0, 0.76, BLUE)
	line([-0.55, -0.55, 0.55, 0.55], 0.15, RED, false)
	if cross:
		line([0.55, -0.55, -0.55, 0.55], 0.15, RED, false)


func _s_no_parking() -> void:
	_blue_ban(false)


func _s_no_stopping() -> void:
	_blue_ban(true)


func _s_no_pedestrians() -> void:
	base_prohibition()
	push(0, 0.02, 0.56)
	walker(INK)
	pop()


func _s_no_bicycles() -> void:
	base_prohibition()
	push(0, 0.04, 0.6)
	bicycle(INK)
	pop()


func _s_no_trucks() -> void:
	base_prohibition()
	push(0, 0.06, 0.58)
	truck(INK, WHITE)
	pop()


func _s_no_horn() -> void:
	base_prohibition()
	push(0, 0, 0.58)
	fill([0.62, -0.09, 0.05, -0.12, -0.55, -0.5, -0.62, -0.5, -0.62, 0.5, -0.55, 0.5, 0.05, 0.12, 0.62, 0.09], INK)
	disc(0.72, 0, 0.17, INK)
	pop()
	slash()


func _s_weight_limit() -> void:
	base_prohibition()
	text("3.5t", 0, 0.0, 0.4, INK, 0.82)


func _s_height_limit() -> void:
	base_prohibition()
	text("3.5m", 0, 0.0, 0.33, INK, 0.82)
	fill([-0.15, -0.66, 0.15, -0.66, 0.0, -0.4], INK)
	fill([-0.15, 0.66, 0.15, 0.66, 0.0, 0.4], INK)


func _s_end_restrictions() -> void:
	base_end_sign()
	end_stripes(7, 0.07, 0.9, 0.032, INK)


# --- mandatory ----------------------------------------------------------------

func _s_ahead_only() -> void:
	base_blue_disc()
	push(0, 0, 0.66)
	up_arrow(WHITE)
	pop()


func _s_turn_right_only() -> void:
	base_blue_disc()
	push(-0.04, 0.05, 0.66)
	_turn_arrow(WHITE, 1.0)
	pop()


func _s_turn_left_only() -> void:
	base_blue_disc()
	push(0.04, 0.05, 0.66)
	_turn_arrow(WHITE, -1.0)
	pop()


func _s_keep_right() -> void:
	base_blue_disc()
	push(0, 0, 0.66)
	arrow([-0.62, -0.62, 0.62, 0.62], 0.26, 0.6, 0.46, WHITE)
	pop()


func _s_roundabout() -> void:
	base_blue_disc()
	push(0, 0, 0.92)
	round_arrows(WHITE)
	pop()


func _s_min_speed_30() -> void:
	base_blue_disc()
	text("30", 0, 0.0, 0.62, WHITE, 0.86)


func _s_cycle_path() -> void:
	base_blue_disc()
	push(0, 0.05, 0.64)
	bicycle(WHITE)
	pop()


func _s_footpath() -> void:
	base_blue_disc()
	push(0, 0.02, 0.6)
	walker(WHITE)
	pop()


# --- warning ------------------------------------------------------------------

func _s_danger() -> void:
	base_warning()
	warn_frame()
	fill([-0.15, -0.95, 0.15, -0.95, 0.08, 0.35, -0.08, 0.35], INK)
	disc(0, 0.68, 0.16, INK)
	pop()


func _s_crossroads() -> void:
	base_warning()
	warn_frame()
	rect(-0.12, -0.95, 0.12, 0.95, INK)
	rect(-0.85, -0.12, 0.85, 0.12, INK)
	pop()


func _s_priority_junction() -> void:
	base_warning()
	warn_frame()
	rect(-0.85, -0.07, 0.85, 0.07, INK)
	fill([-0.08, -0.95, 0.08, -0.95, 0.17, 0.95, -0.17, 0.95], INK)
	pop()


func _curve(dir: float) -> void:
	var pts := [-0.32 * dir, 0.95, -0.32 * dir, 0.2]
	var arc := arc_pts(0.32 * dir, 0.2, 0.64, 180.0 if dir > 0 else 0.0, 245.0 if dir > 0 else -65.0, 12)
	pts.append_array(arc)
	var ea := deg_to_rad(245.0 if dir > 0 else -65.0)
	var tangent := Vector2(-sin(ea), cos(ea)) * (1.0 if dir > 0 else -1.0)
	var end := Vector2(arc[arc.size() - 2], arc[arc.size() - 1])
	var tip := end + tangent * 0.5
	pts.append_array([tip.x, tip.y])
	arrow(pts, 0.24, 0.48, 0.38, INK)


func _s_curve_right() -> void:
	base_warning()
	warn_frame()
	_curve(1.0)
	pop()


func _s_curve_left() -> void:
	base_warning()
	warn_frame()
	_curve(-1.0)
	pop()


func _s_double_curve() -> void:
	base_warning()
	warn_frame()
	var pts := []
	for i in 21:
		var t := float(i) / 20.0
		var y := lerpf(0.95, -0.55, t)
		pts.append_array([-0.34 * sin(t * TAU) + 0.04, y])
	pts.append_array([0.04, -0.98])
	arrow(pts, 0.22, 0.44, 0.36, INK)
	pop()


func _s_ped_crossing_ahead() -> void:
	base_warning()
	warn_frame(0.36)
	push(0, -0.14, 0.84)
	walker(INK)
	pop()
	zebra(INK, 0.76)
	pop()


func _s_children() -> void:
	base_warning()
	warn_frame(0.36)
	push(-0.36, -0.06, 0.88)
	walker(INK, 1.15)
	pop()
	push(0.46, 0.2, 0.62)
	walker(INK, 1.2)
	pop()
	pop()


func _s_cyclists_ahead() -> void:
	base_warning()
	warn_frame(0.36)
	push(0, 0.08, 0.95)
	bicycle(INK)
	pop()
	pop()


func _s_roadworks() -> void:
	base_warning()
	warn_frame(0.36)
	# heap of earth
	fill([0.3, 0.95, 0.5, 0.62, 0.72, 0.5, 0.92, 0.66, 1.0, 0.95], INK)
	# worker leaning on a shovel
	disc(-0.32, -0.74, 0.17, INK)
	line([-0.38, -0.48, -0.12, 0.08], 0.28, INK)
	line([-0.12, 0.08, -0.36, 0.5, -0.58, 0.92], 0.16, INK)
	line([-0.1, 0.08, 0.12, 0.48, 0.06, 0.92], 0.16, INK)
	line([-0.62, -0.5, 0.5, 0.58], 0.07, INK)
	line([-0.3, -0.42, -0.42, -0.14, -0.26, -0.08], 0.12, INK)
	line([-0.24, -0.4, 0.0, -0.18, 0.08, 0.16], 0.12, INK)
	fill([0.4, 0.5, 0.64, 0.44, 0.74, 0.7, 0.5, 0.78], INK)
	pop()


func _s_slippery() -> void:
	base_warning()
	warn_frame(0.38)
	push(0, -0.42, 0.8)
	car_side(INK, WHITE)
	pop()
	for x0 in [-0.28, 0.32]:
		var pts := []
		for i in 13:
			var t := float(i) / 12.0
			pts.append_array([x0 + 0.2 * sin(t * TAU * 1.1) - t * 0.25, lerpf(0.0, 0.95, t)])
		line(pts, 0.08, INK)
	pop()


func _s_traffic_lights() -> void:
	base_warning()
	warn_frame(0.36)
	rrect(-0.32, -0.98, 0.32, 0.98, 0.14, INK)
	disc(0, -0.58, 0.2, LIGHT_RED)
	disc(0, 0.0, 0.2, LIGHT_AMBER)
	disc(0, 0.58, 0.2, LIGHT_GREEN)
	pop()


func _s_level_crossing() -> void:
	base_warning()
	warn_frame(0.38)
	push(0, 0.02, 0.92)
	rrect(-0.82, -0.34, 0.34, 0.16, 0.06, INK)
	rect(0.3, -0.68, 0.86, 0.16, INK)
	rect(0.22, -0.78, 0.94, -0.66, INK)
	rect(0.45, -0.58, 0.72, -0.3, WHITE)
	fill([-0.74, -0.74, -0.44, -0.74, -0.52, -0.33, -0.66, -0.33], INK)
	disc(-0.1, -0.36, 0.12, INK)
	rect(-0.94, 0.14, 0.9, 0.3, INK)
	fill([-0.94, 0.14, -1.02, 0.5, -0.78, 0.3], INK)
	for w in [[-0.6, 0.17], [-0.17, 0.17], [0.5, 0.24]]:
		disc(w[0], 0.52 - (w[1] - 0.17), w[1], INK)
		disc(w[0], 0.52 - (w[1] - 0.17), w[1] * 0.4, WHITE)
	pop()
	pop()


func _s_cattle() -> void:
	base_warning()
	warn_frame(0.38)
	push(0, 0.1, 0.95)
	rrect(-0.72, -0.32, 0.46, 0.26, 0.14, INK)
	fill([0.34, -0.3, 0.58, -0.46, 0.84, -0.36, 0.94, -0.12, 0.8, 0.04, 0.5, 0.0], INK)
	line([0.6, -0.42, 0.52, -0.62], 0.08, INK)
	line([0.76, -0.42, 0.84, -0.6], 0.08, INK)
	for lx in [-0.6, -0.4, 0.18, 0.36]:
		rect(lx - 0.06, 0.15, lx + 0.06, 0.72, INK)
	line([-0.7, -0.24, -0.86, 0.12], 0.06, INK)
	pop()
	pop()


func _s_falling_rocks() -> void:
	base_warning()
	warn_frame(0.38)
	fill([-0.92, 0.95, -0.92, -0.95, -0.55, -0.95, 0.0, 0.95], INK)
	for rk in [[0.12, -0.42, 0.13], [0.36, 0.06, 0.16], [0.62, 0.62, 0.22]]:
		var pts := []
		for k in 6:
			var a := TAU * k / 6.0 + rk[0] * 3.0
			var rr: float = rk[2] * (0.82 + 0.3 * float((k * 7) % 3) / 2.0)
			pts.append_array([rk[0] + cos(a) * rr, rk[1] + sin(a) * rr])
		fill(pts, INK)
	pop()


func _s_road_narrows() -> void:
	base_warning()
	warn_frame()
	for sx in [-1.0, 1.0]:
		line([0.55 * sx, 0.95, 0.55 * sx, 0.3, 0.22 * sx, -0.2, 0.22 * sx, -0.95], 0.16, INK)
	pop()


func _s_two_way() -> void:
	base_warning()
	warn_frame()
	push(-0.3, 0, 0.95)
	arrow([0, -0.9, 0, 0.9], 0.18, 0.46, 0.34, INK)
	pop()
	push(0.3, 0, 0.95)
	arrow([0, 0.9, 0, -0.9], 0.18, 0.46, 0.34, INK)
	pop()
	pop()


func _s_roundabout_ahead() -> void:
	base_warning()
	warn_frame(0.4)
	round_arrows(INK, 0.6, 0.17)
	pop()


func _s_bump() -> void:
	base_warning()
	warn_frame()
	var pts := [-0.95, 0.75, 0.95, 0.75, 0.95, 0.45]
	for i in 17:
		var t := float(i) / 16.0
		var x := lerpf(0.5, -0.5, t)
		pts.append_array([x, 0.45 - sin(t * PI) * 0.5])
	pts.append_array([-0.95, 0.45])
	fill(pts, INK)
	pop()


func _s_steep_descent() -> void:
	base_warning()
	warn_frame(0.4)
	fill([-0.95, -0.65, 0.95, 0.75, -0.95, 0.75], INK)
	text("10%", -0.42, 0.38, 0.3, WHITE, 0.9)
	pop()


# --- information -----------------------------------------------------------------

func _s_one_way() -> void:
	base_blue_square()
	push(0, 0, 0.72)
	up_arrow(WHITE)
	pop()


func _s_ped_crossing() -> void:
	base_blue_square()
	var tri := rounded(_pix([0, -0.78, 0.8, 0.62, -0.8, 0.62]), L(0.08))
	poly_px(tri, WHITE)
	push(0, 0.18, 0.4)
	push(0, -0.1, 0.85)
	walker(INK)
	pop()
	zebra(INK, 0.78)
	pop()


func _s_dead_end() -> void:
	base_blue_square()
	rect(-0.18, -0.36, 0.18, 0.82, WHITE)
	rect(-0.6, -0.64, 0.6, -0.36, RED)


func _s_parking() -> void:
	base_blue_square()
	text("P", 0.02, 0.0, 1.0, WHITE)
