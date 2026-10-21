extends RefCounted
## Headless bots for difficulty measurements (used by tests/difficulty_check.gd
## and tools/sim.gd). Not a test suite itself (no _check suffix).
##   random  : random rotation + random target column, hard drop
##   centre  : "do nothing": hard drop in the spawn column, no rotation
##   greedy  : tries every rotation x column, keeps the best immediate result
##             (clear points first, then fewest holes / lowest stack)


## Hashed deterministic seed for game `i` of a measurement.
static func seed_for(i: int) -> int:
	return hash("pentaprism-bot-%d" % i) & 0x7fffffff


## Plays one game to the end (or `cap` pieces). Returns {pieces, score, ...}.
static func play(kind: String, seed_value: int, cap: int = 400, tune := {}) -> Dictionary:
	var b := PrismBoard.new(9, 16, seed_value)
	for k in tune:
		b.set(k, tune[k])
	b.stones_in = b.stone_interval()
	b.start()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x5bd1e995
	var clearing_pieces := 0
	var matching_pieces := 0 # pieces whose resolution had a colour match
	while b.state == PrismBoard.State.PLAYING and b.pieces_placed < cap:
		match kind:
			"random":
				for r in rng.randi_range(0, 3):
					b.rotate(1)
				var tx := rng.randi_range(0, b.width - 1)
				while b.current.pos.x < tx and b.move(1):
					pass
				while b.current.pos.x > tx and b.move(-1):
					pass
			"greedy":
				var best := best_placement(b)
				if not best.is_empty():
					b.current.cells = best.cells
					b.current.pos.x = best.x
		b.hard_drop()
		if b.state == PrismBoard.State.RESOLVING:
			var steps := b.resolve_all()
			if steps.size() > 1:
				clearing_pieces += 1
			for st in steps:
				if not st.groups.is_empty():
					matching_pieces += 1
					break
	return {"pieces": b.pieces_placed, "score": b.score, "over": b.state == PrismBoard.State.OVER,
		"level": b.level, "chain": b.best_chain, "rows": b.rows_cleared, "cleared": b.cleared_cells,
		"clearing": clearing_pieces, "matching": matching_pieces, "reason": b.over_reason}


## Every reachable (rotation, column) for the current piece, scored on a copy.
static func best_placement(b: PrismBoard) -> Dictionary:
	var best := {}
	var best_v := -INF
	var cells: Array[Vector2i] = b.current.cells.duplicate()
	var seen := []
	var p := b.current
	for r in 4:
		var key := cells.duplicate()
		key.sort()
		if not seen.has(key):
			seen.append(key)
			for x in _reachable_columns(b, cells, p.pos):
				var v := _evaluate(b, cells, p.colors, x)
				if v > best_v:
					best_v = v
					best = {"cells": cells.duplicate(), "x": x, "v": v}
		var nxt: Array[Vector2i] = []
		for c in cells:
			nxt.append(Vector2i(-c.y, c.x))
		cells = nxt
	return best


static func _reachable_columns(b: PrismBoard, cells: Array[Vector2i], pos: Vector2i) -> Array:
	var out := []
	if b.collides(cells, pos):
		return out
	out.append(pos.x)
	for dir in [-1, 1]:
		var x: int = pos.x + dir
		while not b.collides(cells, Vector2i(x, pos.y)):
			out.append(x)
			x += dir
	return out


static func _evaluate(b: PrismBoard, cells: Array[Vector2i], colors: PackedInt32Array, x: int) -> float:
	var s := b.sim_copy()
	var piece := Pieces.Piece.new()
	piece.cells = cells
	piece.colors = colors
	piece.pos = Vector2i(x, b.current.pos.y)
	s.current = piece
	s.state = PrismBoard.State.PLAYING
	s.hard_drop()
	if s.state == PrismBoard.State.OVER:
		return -1e9
	while not s.resolve_step().done:
		pass
	var gain := s.score - b.score
	var holes := 0
	var agg := 0
	var top := 0
	var bump := 0
	var prev_h := -1
	for cx in s.width:
		var h := 0
		var seen_block := false
		for cy in s.height:
			var v := s.grid[cy * s.width + cx]
			if v != 0 and not seen_block:
				seen_block = true
				h = s.height - cy
			elif v == 0 and seen_block:
				holes += 1
		agg += h
		top = maxi(top, h)
		if prev_h >= 0:
			bump += absi(h - prev_h)
		prev_h = h
	var danger := 400.0 if top >= s.height - 4 else 0.0
	return gain * 1.0 - holes * 30.0 - agg * 2.0 - bump * 3.0 - top * 4.0 - danger


static func median(a: Array) -> float:
	var s := a.duplicate()
	s.sort()
	if s.is_empty():
		return 0.0
	var n := s.size()
	return float(s[n / 2]) if n % 2 == 1 else (s[n / 2 - 1] + s[n / 2]) / 2.0
