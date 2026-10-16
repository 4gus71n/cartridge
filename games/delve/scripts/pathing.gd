class_name Pathing
extends RefCounted
## Breadth-first search helpers on a Level (8-way movement, uniform cost).

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]


## Distance (in steps) from (sx, sy) to every passable cell; -1 = unreachable.
static func distance_map(lv: Level, sx: int, sy: int, known_only := false) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(Level.W * Level.H)
	dist.fill(-1)
	if not lv.passable(sx, sy):
		return dist
	var queue := PackedInt32Array([Level.idx(sx, sy)])
	dist[queue[0]] = 0
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		var cx := c % Level.W
		var cy := c / Level.W
		var nd := dist[c] + 1
		for d in DIRS:
			var nx: int = cx + d.x
			var ny: int = cy + d.y
			if not Level.in_bounds(nx, ny):
				continue
			var n := ny * Level.W + nx
			if dist[n] != -1 or lv.tiles[n] == Level.WALL:
				continue
			if known_only and lv.seen[n] == 0:
				continue
			dist[n] = nd
			queue.append(n)
	return dist


## Shortest path from `from` to `to` (excluding `from`). Empty when unreachable.
## `blocked` holds cell indices that may not be entered (e.g. monsters).
static func find_path(lv: Level, from: Vector2i, to: Vector2i, known_only := false, blocked := {}) -> Array:
	if from == to or not Level.in_bounds(to.x, to.y) or not lv.passable(to.x, to.y):
		return []
	if known_only and lv.seen[Level.idx(to.x, to.y)] == 0:
		return []
	var parent := PackedInt32Array()
	parent.resize(Level.W * Level.H)
	parent.fill(-1)
	var start := Level.idx(from.x, from.y)
	var goal := Level.idx(to.x, to.y)
	parent[start] = start
	var queue := PackedInt32Array([start])
	var head := 0
	var found := false
	while head < queue.size():
		var c := queue[head]
		head += 1
		if c == goal:
			found = true
			break
		var cx := c % Level.W
		var cy := c / Level.W
		for d in DIRS:
			var nx: int = cx + d.x
			var ny: int = cy + d.y
			if not Level.in_bounds(nx, ny):
				continue
			var n := ny * Level.W + nx
			if parent[n] != -1 or lv.tiles[n] == Level.WALL:
				continue
			if known_only and lv.seen[n] == 0:
				continue
			if n != goal and blocked.has(n):
				continue
			parent[n] = c
			queue.append(n)
	if not found:
		return []
	var path := []
	var c := goal
	while c != start:
		path.push_front(Vector2i(c % Level.W, c / Level.W))
		c = parent[c]
	return path
