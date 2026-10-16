extends SceneTree
## Headless rules suite: godot --headless --path . --script tests/board_check.gd

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	_adjacency()
	_flood_and_win()
	_lose()
	_flags_and_chord()
	_first_tap_safe()
	_solver_rejects_fifty_fifty()
	_no_guess_generation()
	print("board_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _board(w: int, h: int, mine_cells: Array) -> MineBoard:
	var b := MineBoard.new(w, h, mine_cells.size())
	b.place_mines(PackedInt32Array(mine_cells))
	b.state = MineBoard.State.PLAYING
	return b


func _adjacency() -> void:
	# 3x3 with a mine in the centre: every other cell sees exactly 1.
	var b := _board(3, 3, [4])
	for i in 9:
		if i != 4:
			check(b.adjacent[i] == 1, "adjacent %d == 1" % i)
	check(b.neighbors(0).size() == 3, "corner has 3 neighbours")
	check(b.neighbors(4).size() == 8, "centre has 8 neighbours")


func _flood_and_win() -> void:
	# 5x5, single mine in the bottom-right corner: one tap opens everything.
	var b := _board(5, 5, [24])
	var opened := b.reveal(0)
	check(opened.size() == 24, "flood opens all 24 safe cells (got %d)" % opened.size())
	check(b.state == MineBoard.State.WON, "single tap wins")
	check(b.flagged[24] == 1, "win auto-flags remaining mines")
	check(b.mines_left() == 0, "mines_left is 0 after win")


func _lose() -> void:
	var b := _board(3, 3, [0])
	b.reveal(0)
	check(b.state == MineBoard.State.LOST, "revealing a mine loses")
	check(b.exploded == 0, "exploded cell recorded")
	check(b.reveal(8).is_empty(), "no reveals after losing")


func _flags_and_chord() -> void:
	# Row of 3: mine at 0. Cell 1 shows 1.
	var b := _board(3, 1, [0])
	b.reveal(1)
	check(b.revealed[1] == 1 and b.revealed[2] == 0, "number does not flood")
	check(b.chord(1).is_empty(), "chord needs matching flags")
	check(b.toggle_flag(0), "flag hidden cell")
	check(b.mines_left() == 0, "flag decrements mines_left")
	check(b.reveal(0).is_empty(), "flagged cell can't be revealed")
	var opened := b.chord(1)
	check(opened.size() == 1 and opened[0] == 2, "chord opens unflagged neighbour")
	check(b.state == MineBoard.State.WON, "chord can win")
	check(not b.toggle_flag(1), "can't flag a revealed cell")


func _first_tap_safe() -> void:
	var rng := RandomNumberGenerator.new()
	for s in 40:
		rng.seed = hash(s * 7919 + 13)
		var b := MineBoard.new(12, 20, 44)
		var first := rng.randi_range(0, b.size() - 1)
		b.generate(first, rng, false)
		var count := 0
		for i in b.size():
			count += b.mines[i]
		check(count == 44, "exact mine count (seed %d)" % s)
		check(b.mines[first] == 0 and b.adjacent[first] == 0, "first tap is an opening (seed %d)" % s)


func _solver_rejects_fifty_fifty() -> void:
	# 2x2 board, opening forced at nothing: classic 50/50 needs a guess.
	# Layout (4x2):  . . 1 M        top-right vs bottom-right are
	#                . . 1 .        indistinguishable from the left.
	var b := MineBoard.new(4, 2, 1)
	b.place_mines(PackedInt32Array([3]))
	check(not MineSolver.solvable(b, 0), "solver detects a forced 50/50")
	# Same board with a known count makes it trivially solvable on 3x1.
	var c := MineBoard.new(3, 1, 1)
	c.place_mines(PackedInt32Array([2]))
	check(MineSolver.solvable(c, 0), "solver clears a deterministic board")


func _no_guess_generation() -> void:
	var rng := RandomNumberGenerator.new()
	for d in [[9, 9, 10], [10, 14, 24], [12, 20, 44]]:
		var found := 0
		var t0 := Time.get_ticks_msec()
		for s in 10:
			rng.seed = hash(s * 104729 + d[2])
			var b := MineBoard.new(d[0], d[1], d[2])
			var first := b.index(d[0] / 2, d[1] / 2)
			var attempts := 0
			var ok := false
			for chunk in 30:
				attempts += 1
				if b.generate(first, rng, true, 25):
					ok = true
					break
			if ok:
				found += 1
				# Playing it with the solver must clear it.
				check(MineSolver.solvable(b, first), "generated board is solvable")
		var ms := Time.get_ticks_msec() - t0
		print("  %dx%d/%d: %d/10 no-guess boards, avg %.1f ms" % [d[0], d[1], d[2], found, ms / 10.0])
		check(found == 10, "%dx%d no-guess board always found" % [d[0], d[1]])
