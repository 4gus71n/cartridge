extends SceneTree
## Rules suite: godot --headless --path . --script tests/board_check.gd

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	_shapes()
	_rotation()
	_collision_and_walls()
	_wall_kick()
	_settle()
	_group_clear()
	_row_clear()
	_no_clear_for_three()
	_chain_and_scoring()
	_combo()
	_gravity_and_lock_delay()
	_hard_drop_and_ghost()
	_hold()
	_level_speed()
	_game_over_spawn()
	_game_over_topout()
	_game_over_lock_above()
	print("board_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


## Board from rows of text, '.' empty, digits = hue. Rows align to the bottom.
func _board(rows: Array, w := 6, h := 8) -> PrismBoard:
	var b := PrismBoard.new(w, h, 7)
	var top := h - rows.size()
	for r in rows.size():
		var s: String = rows[r]
		for x in s.length():
			if s[x] != ".":
				b.grid[(top + r) * w + x] = int(s[x])
	b.state = PrismBoard.State.RESOLVING
	return b


func _rows_of(b: PrismBoard) -> Array:
	var out := []
	for y in b.height:
		var s := ""
		for x in b.width:
			var v := b.at(x, y)
			s += "." if v == 0 else str(v)
		out.append(s)
	return out


func _shapes() -> void:
	check(Pieces.SHAPES.size() == 14, "14 shapes (12 pentominoes + 2 trominoes)")
	var fives := 0
	var fours := 0
	for k in Pieces.SHAPES:
		var cells := Pieces.base_cells(k)
		if cells.size() == 5:
			fives += 1
		if cells.size() == 4:
			fours += 1
		# Every shape is a single connected polyomino with no duplicate cells.
		var seen := {}
		for c in cells:
			seen[c] = true
		check(seen.size() == cells.size(), "%s has unique cells" % k)
		var reach := [cells[0]]
		var k2 := 0
		while k2 < reach.size():
			var c: Vector2i = reach[k2]
			k2 += 1
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if seen.has(c + d) and not reach.has(c + d):
					reach.append(c + d)
		check(reach.size() == cells.size(), "%s is connected" % k)
	check(fives == 12, "12 pentominoes")
	check(fours == 0, "no tetrominoes at all")
	var p := Pieces.make("P", [1, 2])
	var a := 0
	for h in p.colors:
		if h == 1:
			a += 1
	check(a == 3 and p.colors.size() == 5, "pentomino split 3+2 hues")
	var t := Pieces.make("i3", [4])
	check(Array(t.colors) == [4, 4, 4], "tromino is a single hue")


func _rotation() -> void:
	var p := Pieces.make("L", [1, 2])
	var orig := p.cells.duplicate()
	var cells := p.cells
	for i in 4:
		p.cells = p.rotated_cells(1)
	check(p.cells == orig, "four clockwise turns return to start")
	p.cells = p.rotated_cells(1)
	p.cells = p.rotated_cells(-1)
	check(p.cells == orig, "cw then ccw is identity")
	var i5 := Pieces.make("I", [1, 2])
	var r := i5.rotated_cells(1)
	var xs := {}
	for c in r:
		xs[c.x] = true
	check(xs.size() == 1, "I rotated is vertical")
	# Colours stay attached to their cells through rotation in the board.
	var b := PrismBoard.new(9, 16, 3)
	b.start()
	var before := b.current.colors.duplicate()
	check(b.rotate(1), "rotate in open space")
	check(b.current.colors == before, "colours keep index order after rotate")
	check(cells != null, "cells sanity")


func _collision_and_walls() -> void:
	var b := PrismBoard.new(9, 16, 1)
	b.start()
	b.current = Pieces.make("I", [1, 2])
	b.current.pos = Vector2i(4, 0)
	var moves := 0
	while b.move(-1):
		moves += 1
	check(moves == 2, "I5 stops at the left wall (moved %d)" % moves)
	check(b.current.pos.x == 2, "I5 pivot x=2 at wall")
	while b.move(1):
		pass
	check(b.current.pos.x == 6, "I5 stops at the right wall")
	b.grid[b.index(4, 1)] = 3
	b.current.pos = Vector2i(4, 0)
	check(b.collides(b.current.cells, Vector2i(4, 1)), "collides with locked gem")
	check(not b.collides(b.current.cells, Vector2i(4, -1)), "above the top is free")
	check(b.collides(b.current.cells, Vector2i(4, 16)), "below floor collides")


func _wall_kick() -> void:
	var b := PrismBoard.new(9, 16, 1)
	b.start()
	b.current = Pieces.make("I", [1, 2])
	b.current.cells = b.current.rotated_cells(1) # vertical
	b.current.pos = Vector2i(0, 5)
	check(b.rotate(1), "vertical I at wall rotates with a kick")
	for c in b.current.cells:
		check(b.current.pos.x + c.x >= 0, "kicked inside the well")
	# Fully boxed in: rotation fails and piece is unchanged.
	var c2 := PrismBoard.new(3, 6, 1)
	c2.start()
	c2.current = Pieces.make("i3", [1])
	c2.current.pos = Vector2i(1, 5)
	for x in 3:
		for y in range(0, 5):
			c2.grid[c2.index(x, y)] = 2
	var before := c2.current.cells.duplicate()
	check(not c2.rotate(1), "boxed-in rotation fails")
	check(c2.current.cells == before, "failed rotation leaves piece intact")


func _settle() -> void:
	var b := _board([
		"1.....",
		"......",
		".2....",
		"......",
	])
	var falls := b.settle()
	check(falls.size() == 2, "two gems fell")
	check(b.at(0, 7) == 1 and b.at(1, 7) == 2, "gems landed on the floor")
	check(b.filled() == 2, "no gems created or lost")
	check(b.settle().is_empty(), "settle is idempotent")


func _group_clear() -> void:
	var b := _board([
		"11....",
		"12....",
		"13....",
	])
	# Column 0 holds 1,1,1 + (0,5) also 1 -> L-shaped group of 4.
	var found := b.find_clears()
	check(found.cells.size() == 4, "L group of four hue-1 gems found (%d)" % found.cells.size())
	check(found.rows.is_empty(), "no full rows")
	var s := b.resolve_step()
	check(not s.done and s.chain == 1, "step cleared with chain 1")
	check(b.filled() == 2, "only the two other gems remain")
	var s2 := b.resolve_step()
	check(s2.done, "nothing more to clear")
	check(b.at(1, 7) == 3 and b.at(1, 6) == 2, "remaining gems settled in order")


func _row_clear() -> void:
	var b := _board([
		"123412",
		"341234",
	])
	var found := b.find_clears()
	check(found.rows.size() == 2, "two full rows found")
	check(found.cells.size() == 12, "row cells all marked")
	b.resolve_step()
	check(b.filled() == 0, "full rows cleared")
	check(b.rows_cleared == 2, "rows_cleared counted")


func _no_clear_for_three() -> void:
	var b := _board(["111..."])
	check(b.find_clears().cells.is_empty(), "three in a row is not enough")
	var d := _board(["1.1.1.", "1.1.1."])
	check(d.find_clears().cells.is_empty(), "diagonal/separate pairs don't connect")


func _chain_and_scoring() -> void:
	# Clearing the 3s drops the top 1 onto the other 1s -> second clear.
	var b := _board([
		"1.....",
		"3.....",
		"3.....",
		"3.....",
		"3.....",
		"1.....",
		"1.....",
		"1.....",
	], 6, 8)
	check(b.points_for(4, 0, 1) == 40, "4 gems chain1 level1 = 40")
	check(b.points_for(6, 1, 2) == (60 + 100) * 2, "row bonus and chain multiplier")
	var steps := []
	while true:
		var s := b.resolve_step()
		steps.append(s)
		if s.done:
			break
	check(steps.size() == 3, "two clear steps then done (%d)" % steps.size())
	check(steps[0].points == 40, "first clear 40 (%d)" % steps[0].points)
	check(steps[1].chain == 2 and steps[1].points == 80, "chain 2 doubles points (%d)" % steps[1].points)
	check(b.score == 120, "score accumulates (%d)" % b.score)
	check(b.best_chain == 2, "best chain recorded")
	check(b.filled() == 0, "board empty after chain")


func _combo() -> void:
	var b := PrismBoard.new(6, 10, 5)
	b.start()
	b.chain = 1
	check(b.finish() == 0 and b.combo == 1, "first clearing piece = combo 1, no bonus")
	b.chain = 1
	check(b.finish() == 50 and b.combo == 2, "second consecutive = 50 bonus")
	b.chain = 0
	b.finish()
	check(b.combo == 0, "a piece without clears resets combo")


func _gravity_and_lock_delay() -> void:
	var b := PrismBoard.new(9, 16, 2)
	b.start()
	var y0 := b.current.pos.y
	b.update(b.fall_interval() * 0.5)
	check(b.current.pos.y == y0, "no fall before the interval")
	b.update(b.fall_interval() * 0.6)
	check(b.current.pos.y == y0 + 1, "falls one row per interval")
	var locked := false
	var t := 0.0
	while not locked and t < 60.0:
		locked = b.update(0.05)
		t += 0.05
	check(locked, "piece eventually locks")
	check(b.state == PrismBoard.State.RESOLVING, "lock enters RESOLVING")
	check(t > PrismBoard.LOCK_DELAY, "lock waits for the lock delay")
	b.resolve_all()
	check(b.state == PrismBoard.State.PLAYING and b.current != null, "next piece spawned")
	check(b.pieces_placed == 1, "pieces_placed counted")


func _hard_drop_and_ghost() -> void:
	var b := PrismBoard.new(9, 16, 4)
	b.start()
	var gy := b.ghost_y()
	var y0 := b.current.pos.y
	var cells := b.current.cells.duplicate()
	var d := b.hard_drop()
	check(d == gy - y0, "hard drop distance equals ghost distance")
	check(b.score == 2 * d, "hard drop scores 2 per row")
	check(b.state == PrismBoard.State.RESOLVING, "hard drop locks")
	var n := 0
	for c in cells:
		n += 1
	b.resolve_all()
	check(b.filled() == n, "locked gems in grid (%d)" % b.filled())
	var s0 := b.score
	check(b.soft_drop(), "soft drop moves")
	check(b.score == s0 + 1, "soft drop scores 1")


func _hold() -> void:
	var b := PrismBoard.new(9, 16, 9)
	b.start()
	var first := b.current.shape
	var next := b.queue[0].shape
	b.rotate(1)
	check(b.hold(), "hold works")
	check(b.held.shape == first, "held piece stored")
	check(b.held.cells == Pieces.base_cells(first), "held piece reset to spawn orientation")
	check(b.current.shape == next, "next piece came in")
	check(not b.hold(), "can't hold twice in a row")
	b.hard_drop()
	b.resolve_all()
	check(b.can_hold, "hold unlocks after a lock")
	var cur := b.current.shape
	check(b.hold(), "swap hold")
	check(b.current.shape == first and b.held.shape == cur, "swap exchanged pieces")


func _level_speed() -> void:
	var b := PrismBoard.new(9, 16, 1)
	var prev := 999.0
	for lv in range(1, 21):
		b.level = lv
		var f := b.fall_interval()
		check(f < prev or f == 0.06, "level %d faster (%.3f)" % [lv, f])
		prev = f
	b.level = 1
	b.cleared_cells = PrismBoard.CELLS_PER_LEVEL - 4
	b.grid[b.index(0, 15)] = 1
	b.grid[b.index(1, 15)] = 1
	b.grid[b.index(2, 15)] = 1
	b.grid[b.index(3, 15)] = 1
	b.state = PrismBoard.State.RESOLVING
	b.resolve_step()
	check(b.level == 2, "level up after %d cleared gems" % PrismBoard.CELLS_PER_LEVEL)


func _game_over_spawn() -> void:
	var b := PrismBoard.new(9, 16, 1)
	b.start()
	for x in 9:
		b.grid[b.index(x, 0)] = ((x + 1) % 4) + 1
		b.grid[b.index(x, 1)] = (x % 4) + 1
		b.grid[b.index(x, 2)] = ((x + 2) % 4) + 1
	b.state = PrismBoard.State.RESOLVING
	b.current = null
	check(not b.spawn(), "spawn into blocked rows fails")
	check(b.state == PrismBoard.State.OVER, "state OVER")
	check(not b.move(1) and not b.rotate(1) and b.hard_drop() == 0, "no moves after game over")


func _game_over_topout() -> void:
	# Bot plays centre hard drops only: must end in OVER, never hang.
	var b := PrismBoard.new(9, 16, 11)
	b.start()
	var n := 0
	while b.state != PrismBoard.State.OVER and n < 500:
		b.hard_drop()
		if b.state == PrismBoard.State.RESOLVING:
			b.resolve_all()
		n += 1
	check(b.state == PrismBoard.State.OVER, "centre-stacking bot tops out (%d pieces)" % n)
	check(n < 500, "game over reached quickly")
	check(b.score > 0, "bot scored something")


func _game_over_lock_above() -> void:
	# A piece that locks partly above the well ends the game.
	var b := PrismBoard.new(9, 16, 1)
	b.start()
	for y in range(1, 16):
		b.grid[b.index(4, y)] = (y % 4) + 1
	b.current = Pieces.make("I", [1, 2])
	b.current.cells = b.current.rotated_cells(1) # vertical, cells y -2..2
	b.current.pos = Vector2i(4, -2)
	check(b.grounded(), "vertical I resting on a full column")
	b.lock()
	check(b.state == PrismBoard.State.OVER, "locking above the top is game over")
	check(b.pieces_placed == 1, "piece still counted")
