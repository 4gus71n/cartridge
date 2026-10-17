class_name MiniMap
extends Control
## Whole-floor overview of everything the player remembers.

var run: Run


func _draw() -> void:
	if run == null:
		return
	var lv := run.lv
	var cs := floorf(minf(size.x / Level.W, size.y / Level.H))
	var o := ((size - Vector2(Level.W, Level.H) * cs) / 2.0).floor()
	for y in Level.H:
		for x in Level.W:
			var i := Level.idx(x, y)
			if lv.seen[i] == 0:
				continue
			var t := lv.tiles[i]
			var col := Color("#3b3452")
			match t:
				Level.FLOOR, Level.UPSTAIRS:
					col = Color("#2a2638") if run.fov[i] == 0 else Color("#4a4462")
				Level.CORRIDOR:
					col = Color("#231f30") if run.fov[i] == 0 else Color("#3f3a55")
				Level.DOOR, Level.OPEN_DOOR:
					col = Color("#a0683a")
				Level.STAIRS:
					col = Color("#ff9e3d")
				Level.WALL:
					col = Color("#4c4466")
			draw_rect(Rect2(o + Vector2(x, y) * cs, Vector2(cs, cs)), col)
	for e in lv.items:
		if e.s:
			draw_rect(Rect2(o + Vector2(e.x, e.y) * cs + Vector2(cs * 0.25, cs * 0.25), Vector2(cs * 0.5, cs * 0.5)), run.item_color(e.it))
	for m in lv.monsters:
		if run.can_see(m):
			draw_circle(o + (Vector2(m.x, m.y) + Vector2(0.5, 0.5)) * cs, cs * 0.4, Color(Defs.mon(m.t).c))
	if lv.stairs.x >= 0 and lv.seen[Level.idx(lv.stairs.x, lv.stairs.y)] == 1:
		draw_arc(o + (Vector2(lv.stairs) + Vector2(0.5, 0.5)) * cs, cs * 1.1, 0, TAU, 20, Color("#ff9e3d"), 2.0, true)
	var pc := o + (Vector2(run.px, run.py) + Vector2(0.5, 0.5)) * cs
	draw_circle(pc, cs * 0.75, Color("#fff1d6"))
	draw_arc(pc, cs * 1.4, 0, TAU, 20, Color("#ff9e3d"), 2.5, true)
