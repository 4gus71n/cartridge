class_name Fov
extends RefCounted
## Recursive shadowcasting field of view (8 octants). Walls and closed doors
## block sight; the blocking cell itself is visible.

const MULT := [
	[1, 0, 0, -1, -1, 0, 0, 1],
	[0, 1, -1, 0, 0, -1, 1, 0],
	[0, 1, 1, 0, 0, -1, -1, 0],
	[1, 0, 0, 1, -1, 0, 0, -1],
]


static func compute(lv: Level, ox: int, oy: int, radius: int) -> PackedByteArray:
	var vis := PackedByteArray()
	vis.resize(Level.W * Level.H)
	if not Level.in_bounds(ox, oy):
		return vis
	vis[Level.idx(ox, oy)] = 1
	for oct in 8:
		_cast(lv, vis, ox, oy, 1, 1.0, 0.0, radius, MULT[0][oct], MULT[1][oct], MULT[2][oct], MULT[3][oct])
	return vis


static func _cast(lv: Level, vis: PackedByteArray, cx: int, cy: int, row: int, start: float, end: float,
		radius: int, xx: int, xy: int, yx: int, yy: int) -> void:
	if start < end:
		return
	var r2 := radius * radius + radius
	var new_start := 0.0
	for j in range(row, radius + 1):
		var dx := -j - 1
		var dy := -j
		var blocked := false
		while dx <= 0:
			dx += 1
			var x := cx + dx * xx + dy * xy
			var y := cy + dx * yx + dy * yy
			var l_slope := (dx - 0.5) / (dy + 0.5)
			var r_slope := (dx + 0.5) / (dy - 0.5)
			if start < r_slope:
				continue
			elif end > l_slope:
				break
			var inb := Level.in_bounds(x, y)
			if inb and dx * dx + dy * dy <= r2:
				vis[y * Level.W + x] = 1
			var opaque := (not inb) or lv.opaque(x, y)
			if blocked:
				if opaque:
					new_start = r_slope
					continue
				blocked = false
				start = new_start
			elif opaque and j < radius:
				blocked = true
				_cast(lv, vis, cx, cy, j + 1, start, l_slope, radius, xx, xy, yx, yy)
				new_start = r_slope
		if blocked:
			break


## Bresenham line from a to b (excluding a), clipped at max_len cells.
static func line(a: Vector2i, b: Vector2i, max_len := 99) -> Array:
	var out := []
	var delta := (b - a).abs()
	var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var err := delta.x - delta.y
	var p := a
	while p != b and out.size() < max_len:
		var e2 := err * 2
		if e2 > -delta.y:
			err -= delta.y
			p.x += step.x
		if e2 < delta.x:
			err += delta.x
			p.y += step.y
		out.append(p)
	return out
