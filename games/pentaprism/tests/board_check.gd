extends SceneTree
## Rules suite (v2 stone-rise rules): godot --headless --path . --script tests/board_check.gd

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
	_rigid_lock_leaves_holes()
	_gravity_only_after_clears()
	_penta_match()
	_four_is_not_enough()
	_row_clear_with_stones()
	_stones_never_match()
	_stone_cracking()
	_no_match_scores_zero()
	_chain_and_scoring()
	_combo()
	_gravity_and_lock_delay()
	_hard_drop_and_ghost()
	_hold()
	_level_speed_and_stone_interval()
	_start_rows()
	_stone_rise()
	_countdown()
	_game_over_spawn()
	_game_over_rise()
	_game_over_lock_above()
	print("board_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


## Board from rows of text, '.' empty, digits = hue, '#' = stone. Rows align
## to the bottom.
func _board(rows: Array, w := 6, h := 8) -> PrismBoard:
	var b := PrismBoard.new(w, h, 7)
	var top := h - rows.size()
	for r in rows.size():
		var s: String = rows[r]
		for x in s.length():
			if s[x] == "#":
				b.grid[(top + r) * w + x] = PrismBoard.STONE
			elif s[x] != ".":
				b.grid[(top + r) * w + x] = int(s[x])
	b.state = PrismBoard.State.RESOLVING
	while b.queue.size() < PrismBoard.PREVIEW:
		b.queue.append(b.bag.next_piece())
	return b


## Rotates `rot` times and walks to column `tx` through the real API.
func _place(b: PrismBoard, tx: int, rot: int) -> void:
	for r in rot:
		b.rotate(1)
	while b.current.pos.x < tx and b.move(1):
		pass
	while b.current.pos.x > tx and b.move(-1):
		pass


func _rows_of(b: PrismBoard) -> Array:
	var out := []
	for y in b.height:
		var s := ""
		for x in b.width:
			var v := b.at(x, y)
			s += "." if v == 0 else ("#" if v == PrismBoard.STONE else str(v))
		out.append(s)
	return out


## Puts `piece` at `pos` and locks it there (as a hard drop would).
func _drop(b: PrismBoard, piece: Pieces.Piece, x: int) -> void:
	b.state = PrismBoard.State.PLAYING
	piece.pos = Vector2i(x, -piece.min_y())
	b.current = piece
	b.hard_drop()


func _shapes() -> void:
	check(Pieces.SHAPES.size() == 14, "14 shapes (12 pentominoes + 2 trominoes)")
	check(Pieces.COLORS == 5, "five gem colours")
	var fives := 0
	for k in Pieces.SHAPES:
		var cells := Pieces.base_cells(k)
		if cells.size() == 5:
			fives += 1
		check(cells.size() != 4, "%s is not a tetromino" % k)
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
	for i in 4:
		p.cells = p.rotated_cells(1)
	check(p.cells == orig, "four clockwise turns return to start")
	p.cells = p.rotated_cells(1)
	p.cells = p.rotated_cells(-1)
	check(p.cells == orig, "cw then ccw is identity")
	var i5 := Pieces.make("I", [1, 2])
	var xs := {}
	for c in i5.rotated_cells(1):
		xs[c.x] = true
	check(xs.size() == 1, "I rotated is vertical")
	var b := PrismBoard.new(9, 16, 3)
	b.start(0)
	var before := b.current.colors.duplicate()
	check(b.rotate(1), "rotate in open space")
	check(b.current.colors == before, "colours keep index order after rotate")


func _collision_and_walls() -> void:
	var b := PrismBoard.new(9, 16, 1)
	b.start(0)
	b.current = Pieces.make("I", [1, 2])
	b.current.pos = Vector2i(4, 0)
	var moves := 0
	while b.move(-1):
		moves += 1
	check(moves == 2 and b.current.pos.x == 2, "I5 stops at the left wall (moved %d)" % moves)
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
	b.start(0)
	b.current = Pieces.make("I", [1, 2])
	b.current.cells = b.current.rotated_cells(1)
	b.current.pos = Vector2i(0, 5)
	check(b.rotate(1), "vertical I at wall rotates with a kick")
	var inside := true
	for c in b.current.cells:
		inside = inside and b.current.pos.x + c.x >= 0
	check(inside, "kicked inside the well")
	var c2 := PrismBoard.new(3, 6, 1)
	c2.start(0)
	c2.current = Pieces.make("i3", [1])
	c2.current.pos = Vector2i(1, 5)
	for x in 3:
		for y in range(0, 5):
			c2.grid[c2.index(x, y)] = 2
	var before := c2.current.cells.duplicate()
	check(not c2.rotate(1), "boxed-in rotation fails")
	check(c2.current.cells == before, "failed rotation leaves piece intact")


func _rigid_lock_leaves_holes() -> void:
	# A T dropped onto a single gem: the overhanging arms stay up, holes remain.
	var b := _board([
		"......",
		"......",
		"..4...",
	])
	# T = bar of three on top (hue 1), stem of two below (hue 2).
	_drop(b, Pieces.make("T", [1, 2]), 2)
	var rows := _rows_of(b)
	check(rows[7] == "..4...", "floor gem untouched (%s)" % rows[7])
	check(rows[6] == "..2...", "stem rests on the gem (%s)" % rows[6])
	check(rows[4] == ".111..", "bar stays up in the air (%s)" % rows[4])
	check(b.at(1, 7) == 0 and b.at(1, 6) == 0 and b.at(1, 5) == 0, "holes under the overhang stay open")
	var steps := b.resolve_all()
	check(steps.size() == 1 and steps[0].falls.is_empty(), "no gem moves after a non-clearing lock")
	check(b.at(1, 7) == 0 and b.at(1, 4) != 0, "overhang still floating after resolution")


func _gravity_only_after_clears() -> void:
	# Hue-1 run of 5 clears; the 3 above it falls in, but the old hole in
	# column 0 below the cleared cell (row 7 empty under a 2) stays a hole.
	var b := _board([
		"3.....",
		"2.....",
		"11111.",
		"2.....",
		"......",
	], 6, 8)
	var s := b.resolve_step()
	check(not s.done and s.groups.size() == 1 and s.cells.size() == 5, "penta run cleared")
	var s2 := b.resolve_step()
	check(not s2.falls.is_empty(), "gems above the clear fall")
	var rows := _rows_of(b)
	check(rows[5] == "2....." and rows[4] == "3.....", "column 0 dropped by one into the gap (%s / %s)" % [rows[4], rows[5]])
	check(rows[6] == "2....." and rows[7] == "......", "gem below the clear and its hole untouched")
	check(s2.done, "nothing more")


func _penta_match() -> void:
	var b := _board([
		"11....",
		"12....",
		"13....",
		"1.....",
	])
	var found := b.find_clears()
	check(found.cells.size() == 5, "L group of five hue-1 gems found (%d)" % found.cells.size())
	var s := b.resolve_step()
	check(not s.done and s.chain == 1 and s.points == 50, "5 gems x10 at chain 1 (%d)" % s.points)
	check(b.filled() == 2, "only the two other gems remain")


func _four_is_not_enough() -> void:
	var b := _board(["1111..", "2.....", "2.2..."])
	check(b.find_clears().cells.is_empty(), "four in a row is not enough")
	var d := _board(["1.1.1.", "1.1.1."])
	check(d.find_clears().cells.is_empty(), "separate pairs don't connect")


func _row_clear_with_stones() -> void:
	var b := _board([
		"123451",
		"##1###",
	])
	var found := b.find_clears()
	check(found.rows.size() == 2, "two full rows (stones count)")
	b.resolve_step()
	check(b.filled() == 0 and b.stones() == 0, "prism lines clear stones too")
	check(b.rows_cleared == 2, "rows_cleared counted")
	var c := _board(["##.###"])
	check(c.find_clears().cells.is_empty(), "stone row with a gap does not clear")


func _stones_never_match() -> void:
	var b := _board(["#####.", "#.....", "#....."])
	check(b.find_clears().cells.is_empty(), "seven connected stones never match")


func _stone_cracking() -> void:
	# Hue-2 run of five on top of stones: the stones under it crack; the stone
	# not touching a cleared gem stays.
	var b := _board([
		"22222.",
		"#####.",
		"#.....",
	])
	var s := b.resolve_step()
	check(s.cracks.size() == 5, "five stones touching the clear cracked (%d)" % s.cracks.size())
	var ok := true
	for i in s.cracks:
		ok = ok and PrismBoard.is_gem(b.grid[i]) and b.grid[i] == s.cracks[i]
	check(ok, "cracked stones became coloured gems")
	check(b.at(0, 7) == PrismBoard.STONE, "stone two cells away stays stone")
	check(b.stones_cracked == 5, "cracks counted")
	# Diagonal contact doesn't crack.
	var d := _board([
		".11111",
		"#.....",
	])
	check(d.resolve_step().cracks.is_empty(), "diagonal stone doesn't crack")


func _no_match_scores_zero() -> void:
	var b := PrismBoard.new(9, 16, 5)
	b.start(0)
	var s0 := b.score
	b.hard_drop()
	b.resolve_all()
	check(b.score == s0 and b.score == 0, "a plain placement on an empty well scores 0 (%d)" % b.score)
	check(b.soft_drop() and b.score == 0, "soft drop moves and scores nothing")
	# Random non-matching placements over many pieces: score stays 0 while no
	# step clears anything.
	var c := PrismBoard.new(9, 16, 77)
	c.start(0)
	var clean := true
	for i in 6:
		var x0 := c.score
		_place(c, 1 + i, i % 2)
		c.hard_drop()
		if c.state != PrismBoard.State.RESOLVING:
			break
		var steps := c.resolve_all()
		if steps.size() == 1 and c.score != x0:
			clean = false
	check(clean, "placements without a match/line never change the score")


func _chain_and_scoring() -> void:
	# Clearing the 3s lets the top 1 fall onto the other 1s -> second clear.
	var b := _board([
		"1.....",
		"3.....",
		"3.....",
		"3.....",
		"3.....",
		"3.....",
		"1.....",
		"1.....",
		"1.....",
		"1.....",
	], 6, 10)
	check(b.points_for(5, 0, 1) == 50, "5 gems chain1 level1 = 50")
	check(b.points_for(6, 1, 2) == (60 + 100) * 2, "row bonus and chain multiplier")
	var steps := []
	while true:
		var s := b.resolve_step()
		steps.append(s)
		if s.done:
			break
	check(steps.size() == 3, "two clear steps then done (%d)" % steps.size())
	check(steps[0].points == 50, "first clear 50 (%d)" % steps[0].points)
	check(steps[1].chain == 2 and steps[1].points == 100, "chain 2 doubles points (%d)" % steps[1].points)
	check(b.score == 150, "score accumulates (%d)" % b.score)
	check(b.best_chain == 2, "best chain recorded")
	check(b.filled() == 0, "board empty after chain")


func _combo() -> void:
	var b := PrismBoard.new(6, 10, 5)
	b.start(0)
	b.stones_in = 99
	b.chain = 1
	check(b.finish() == 0 and b.combo == 1, "first clearing piece = combo 1, no bonus")
	b.chain = 1
	check(b.finish() == 50 and b.combo == 2, "second consecutive = 50 bonus")
	b.chain = 0
	b.finish()
	check(b.combo == 0, "a piece without clears resets combo")


func _gravity_and_lock_delay() -> void:
	var b := PrismBoard.new(9, 16, 2)
	b.start(0)
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
	check(locked and b.state == PrismBoard.State.RESOLVING, "piece locks and enters RESOLVING")
	check(t > PrismBoard.LOCK_DELAY, "lock waits for the lock delay")
	b.resolve_all()
	check(b.state == PrismBoard.State.PLAYING and b.current != null, "next piece spawned")
	check(b.pieces_placed == 1, "pieces_placed counted")


func _hard_drop_and_ghost() -> void:
	var b := PrismBoard.new(9, 16, 4)
	b.start(0)
	var gy := b.ghost_y()
	var y0 := b.current.pos.y
	var n := b.current.cells.size()
	var d := b.hard_drop()
	check(d == gy - y0, "hard drop distance equals ghost distance")
	check(b.score == 0, "hard drop scores nothing")
	check(b.state == PrismBoard.State.RESOLVING, "hard drop locks")
	b.resolve_all()
	check(b.filled() == n, "locked gems in grid (%d)" % b.filled())


func _hold() -> void:
	var b := PrismBoard.new(9, 16, 9)
	b.start(0)
	var first := b.current.shape
	var next := b.queue[0].shape
	b.rotate(1)
	check(b.hold(), "hold works")
	check(b.held.shape == first and b.held.cells == Pieces.base_cells(first), "held piece stored in spawn orientation")
	check(b.current.shape == next, "next piece came in")
	check(not b.hold(), "can't hold twice in a row")
	b.hard_drop()
	b.resolve_all()
	check(b.can_hold, "hold unlocks after a lock")
	var cur := b.current.shape
	check(b.hold() and b.current.shape == first and b.held.shape == cur, "swap exchanged pieces")


func _level_speed_and_stone_interval() -> void:
	var b := PrismBoard.new(9, 16, 1)
	var prev := 999.0
	var prev_n := 999
	for lv in range(1, 21):
		b.level = lv
		var f := b.fall_interval()
		check(f < prev or f == 0.06, "level %d faster (%.3f)" % [lv, f])
		prev = f
		var n := b.stone_interval()
		check(n <= prev_n and n >= PrismBoard.STONE_MIN, "level %d stone interval %d" % [lv, n])
		prev_n = n
	b.level = 1
	check(b.stone_interval() == PrismBoard.STONE_START, "level 1 interval = %d" % PrismBoard.STONE_START)
	b.level = 20
	check(b.stone_interval() == PrismBoard.STONE_MIN, "max level interval = %d" % PrismBoard.STONE_MIN)
	b.level = 1
	b.cleared_cells = PrismBoard.CELLS_PER_LEVEL - 5
	for x in 5:
		b.grid[b.index(x, 15)] = 1
	b.state = PrismBoard.State.RESOLVING
	b.resolve_step()
	check(b.level == 2, "level up after %d cleared cells" % PrismBoard.CELLS_PER_LEVEL)


func _start_rows() -> void:
	var b := PrismBoard.new(9, 16, 12)
	b.start()
	check(b.stones() >= 2 * 7 and b.stones() <= 2 * 8, "two starting stone rows (%d stones)" % b.stones())
	for y in range(0, 14):
		for x in 9:
			if b.at(x, y) != 0:
				check(false, "only the bottom rows are filled at start")
	check(b.stones_in == PrismBoard.STONE_START, "countdown starts at %d" % PrismBoard.STONE_START)


func _stone_rise() -> void:
	var b := _board([
		"12....",
		"3.....",
	], 6, 8)
	b.next_gaps = PackedInt32Array([2, 4])
	var topped := b.rise()
	var rows := _rows_of(b)
	check(not topped, "rise with room is not a top-out")
	check(rows[5] == "12...." and rows[6] == "3.....", "stack pushed up one row (%s/%s)" % [rows[5], rows[6]])
	check(rows[7] == "##.#.#", "stone row with gaps at columns 2 and 4 (%s)" % rows[7])
	check(b.next_gaps.size() >= 1 and b.next_gaps.size() <= 2, "next row has 1-2 gaps")
	# Gap counts over many rows are always 1 or 2, distinct, in range.
	var c := PrismBoard.new(9, 16, 99)
	var ok := true
	var ones := 0
	for i in 200:
		var g := c.next_gaps
		ok = ok and g.size() >= 1 and g.size() <= 2
		if g.size() == 2:
			ok = ok and g[0] != g[1]
		else:
			ones += 1
		for x in g:
			ok = ok and x >= 0 and x < 9
		c.grid.fill(0)
		c.rise()
	check(ok, "stone gaps always 1-2 distinct columns")
	check(ones > 50 and ones < 150, "both gap counts happen (%d single)" % ones)


func _countdown() -> void:
	var b := PrismBoard.new(9, 16, 21)
	b.start(0)
	var n := b.stones_in
	check(n == PrismBoard.STONE_START, "countdown starts full")
	for i in n - 1:
		_place(b, (i * 3) % 9, i % 4)
		b.hard_drop()
		if b.state != PrismBoard.State.RESOLVING:
			break
		b.resolve_all()
		check(not b.rose, "no stone row before the countdown ends (piece %d)" % (i + 1))
	check(b.stones_in == 1, "countdown at 1 after %d pieces (%d)" % [n - 1, b.stones_in])
	var stones0 := b.stones()
	b.hard_drop()
	b.resolve_all()
	check(b.rose, "stone row rose on the Nth piece")
	check(b.stones() >= stones0 + 7, "a new stone row is in the well")
	check(b.stones_in == b.stone_interval(), "countdown reset")
	var full := true
	for x in 9:
		if b.at(x, 15) == 0:
			full = false
	check(not full, "bottom stone row has a gap")


func _game_over_spawn() -> void:
	var b := PrismBoard.new(9, 16, 1)
	b.start(0)
	for x in 9:
		b.grid[b.index(x, 0)] = (x % 5) + 1
		b.grid[b.index(x, 1)] = ((x + 2) % 5) + 1
		b.grid[b.index(x, 2)] = ((x + 4) % 5) + 1
	b.state = PrismBoard.State.RESOLVING
	b.current = null
	check(not b.spawn(), "spawn into blocked rows fails")
	check(b.state == PrismBoard.State.OVER and b.over_reason == "spawn", "state OVER (spawn)")
	check(not b.move(1) and not b.rotate(1) and b.hard_drop() == 0, "no moves after game over")


func _game_over_rise() -> void:
	# A column touching the ceiling: the next stone row pushes it out.
	var b := PrismBoard.new(9, 16, 3)
	b.start(0)
	for y in range(0, 16):
		b.grid[b.index(0, y)] = PrismBoard.STONE
	b.hard_drop()
	b.stones_in = 1
	b.resolve_all()
	check(b.rose and b.state == PrismBoard.State.OVER, "stone row pushing the stack out ends the game")
	check(b.over_reason == "rise", "reason rise (%s)" % b.over_reason)
	check(b.current == null, "no piece after a rise top-out")


func _game_over_lock_above() -> void:
	var b := PrismBoard.new(9, 16, 1)
	b.start(0)
	for y in range(1, 16):
		b.grid[b.index(4, y)] = (y % 5) + 1
	b.current = Pieces.make("I", [1, 2])
	b.current.cells = b.current.rotated_cells(1)
	b.current.pos = Vector2i(4, -2)
	check(b.grounded(), "vertical I resting on a full column")
	b.lock()
	check(b.state == PrismBoard.State.OVER and b.over_reason == "lock", "locking above the top is game over")
	check(b.pieces_placed == 1, "piece still counted")
