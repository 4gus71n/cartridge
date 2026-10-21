class_name Gem
extends RefCounted
## Draws Pentaprism's faceted gems (chamfered octagon + bevel facets + a
## per-hue glyph so colours stay distinguishable for colour-blind players).

const HUES := [
	Color(0, 0, 0, 0),
	Color("#ff4f7b"), # rose   · circle
	Color("#ffb23f"), # amber  · triangle
	Color("#2fd3e0"), # aqua   · diamond
	Color("#8f6bff"), # violet · cross
	Color("#7be05a"), # lime   · ring
]
const STONE_COL := Color("#5a556e")


static func color(hue: int) -> Color:
	if hue == PrismBoard.STONE:
		return STONE_COL
	return HUES[clampi(hue, 0, HUES.size() - 1)]


## Stone block: flat, square, rough and grey so it never reads as a gem.
## `seed_i` varies the crack pattern per cell; `flash` 0..1 towards white.
static func draw_stone(ci: CanvasItem, r: Rect2, seed_i: int, flash := 0.0, alpha := 1.0, grey := 0.0) -> void:
	var s := minf(r.size.x, r.size.y)
	if s < 3.0 or alpha <= 0.01:
		return
	var base := STONE_COL.lerp(Color(0.25, 0.25, 0.28), grey).lerp(Color.WHITE, flash)
	var rr := r.grow(s * 0.01)
	ci.draw_rect(rr, _a(base.darkened(0.35), alpha))
	var inner := rr.grow(-s * 0.09)
	ci.draw_rect(Rect2(rr.position, Vector2(rr.size.x, s * 0.09)), _a(base.lightened(0.28), alpha))
	ci.draw_rect(Rect2(rr.position, Vector2(s * 0.09, rr.size.y)), _a(base.lightened(0.12), alpha))
	ci.draw_rect(inner, _a(base, alpha))
	# Rough speckles + a crack, deterministic per cell.
	var h := (seed_i * 2654435761) & 0xffff
	for k in 4:
		var hx := float((h >> (k * 3)) & 7) / 7.0
		var hy := float((h >> (k * 3 + 6)) & 7) / 7.0
		var p := inner.position + Vector2(hx, hy) * (inner.size - Vector2(s, s) * 0.12)
		ci.draw_rect(Rect2(p, Vector2(s, s) * 0.1), _a(base.darkened(0.25), alpha))
	var a := inner.position + Vector2(inner.size.x * (0.2 + 0.5 * float(h & 3) / 3.0), 0)
	var m := inner.get_center() + Vector2((float((h >> 4) & 3) - 1.5) * s * 0.08, 0)
	var b := Vector2(inner.end.x - inner.size.x * (0.2 + 0.4 * float((h >> 8) & 3) / 3.0), inner.end.y)
	ci.draw_polyline(PackedVector2Array([a, m, b]), _a(base.darkened(0.55), alpha), maxf(1.5, s * 0.05))


static func _octagon(r: Rect2, c: float) -> PackedVector2Array:
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	return PackedVector2Array([
		Vector2(x + c, y), Vector2(x + w - c, y), Vector2(x + w, y + c), Vector2(x + w, y + h - c),
		Vector2(x + w - c, y + h), Vector2(x + c, y + h), Vector2(x, y + h - c), Vector2(x, y + c),
	])


## Draws one gem filling `r`. `flash` 0..1 blends towards white,
## `alpha` fades the whole gem, `grey` 0..1 desaturates (game over).
static func draw(ci: CanvasItem, r: Rect2, hue: int, flash := 0.0, alpha := 1.0, grey := 0.0) -> void:
	var base := color(hue)
	if grey > 0.0:
		var l := base.get_luminance() * 0.55
		base = base.lerp(Color(l, l, l * 1.1), grey)
	base = base.lerp(Color.WHITE, flash)
	var s := minf(r.size.x, r.size.y)
	if s < 3.0 or alpha <= 0.01:
		return
	var c := s * 0.2
	var outer := _octagon(r, c)
	var inset := s * 0.22
	var inner := r.grow(-inset)
	var itl := inner.position
	var itr := Vector2(inner.end.x, inner.position.y)
	var ibr := inner.end
	var ibl := Vector2(inner.position.x, inner.end.y)
	var a := alpha
	ci.draw_colored_polygon(outer, _a(base.darkened(0.1), a))
	ci.draw_colored_polygon(PackedVector2Array([outer[0], outer[1], itr, itl]), _a(base.lightened(0.42), a))
	ci.draw_colored_polygon(PackedVector2Array([outer[7], itl, ibl, outer[6]]), _a(base.lightened(0.15), a))
	ci.draw_colored_polygon(PackedVector2Array([outer[2], outer[3], ibr, itr]), _a(base.darkened(0.22), a))
	ci.draw_colored_polygon(PackedVector2Array([outer[4], outer[5], ibl, ibr]), _a(base.darkened(0.42), a))
	ci.draw_colored_polygon(PackedVector2Array([outer[1], outer[2], itr]), _a(base.lightened(0.2), a))
	ci.draw_colored_polygon(PackedVector2Array([outer[5], outer[6], ibl]), _a(base.darkened(0.25), a))
	ci.draw_rect(inner, _a(base.lightened(0.06), a))
	_glyph(ci, inner.get_center(), inner.size.x * 0.32, hue, _a(Color(1, 1, 1, 0.55 * (1.0 - grey * 0.6)), a))
	# Specular glint.
	ci.draw_colored_polygon(PackedVector2Array([
		itl + Vector2(s * 0.04, s * 0.04), itl + Vector2(s * 0.2, s * 0.04), itl + Vector2(s * 0.04, s * 0.2),
	]), _a(Color(1, 1, 1, 0.45), a))


## Hollow outline for the ghost piece.
static func draw_ghost(ci: CanvasItem, r: Rect2, hue: int) -> void:
	var s := minf(r.size.x, r.size.y)
	if s < 3.0:
		return
	var pts := _octagon(r.grow(-s * 0.06), s * 0.2)
	pts.append(pts[0])
	var col := color(hue)
	ci.draw_colored_polygon(_octagon(r.grow(-s * 0.06), s * 0.2), Color(col, 0.10))
	ci.draw_polyline(pts, Color(col, 0.6), maxf(1.5, s * 0.05), true)


static func _glyph(ci: CanvasItem, p: Vector2, rad: float, hue: int, col: Color) -> void:
	match hue:
		1:
			ci.draw_circle(p, rad * 0.8, col)
		2:
			ci.draw_colored_polygon(PackedVector2Array([
				p + Vector2(0, -rad), p + Vector2(rad * 0.95, rad * 0.7), p + Vector2(-rad * 0.95, rad * 0.7),
			]), col)
		3:
			ci.draw_colored_polygon(PackedVector2Array([
				p + Vector2(0, -rad), p + Vector2(rad, 0), p + Vector2(0, rad), p + Vector2(-rad, 0),
			]), col)
		4:
			var t := rad * 0.36
			ci.draw_rect(Rect2(p - Vector2(rad, t), Vector2(rad * 2, t * 2)), col)
			ci.draw_rect(Rect2(p - Vector2(t, rad), Vector2(t * 2, rad * 2)), col)
		5:
			ci.draw_arc(p, rad * 0.68, 0, TAU, 20, col, rad * 0.42)


static func _a(c: Color, a: float) -> Color:
	return Color(c, c.a * a)
