extends SceneTree
## Every bundled puzzle: well-formed, unique solution, graded at its level,
## no duplicates across the pool.
## godot --headless --path . --script tests/pool_check.gd

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var seen := {}
	var total := 0
	for lv in [1, 2, 3]:
		var pool: Array = SudokuGame.pool_for(lv)
		check(pool.size() >= 100, "level %d has a big pool (%d)" % [lv, pool.size()])
		var bad_unique := 0
		var bad_grade := 0
		var bad_form := 0
		var clues := 0
		for s: String in pool:
			total += 1
			if s.length() != 81 or seen.has(s):
				bad_form += 1
			seen[s] = true
			var g := SudokuGrid.parse(s)
			clues += SudokuGrid.count_givens(g)
			if SudokuGrid.count_givens(g) < 17 or not SudokuGrid.is_consistent(g):
				bad_form += 1
			if SudokuSolver.count_solutions(g, 2) != 1:
				bad_unique += 1
				printerr("not unique: ", s)
			var a := SudokuGrader.analyze(g)
			if a.level != lv or not a.solved:
				bad_grade += 1
				printerr("grade %d != %d: %s" % [a.level, lv, s])
		check(bad_form == 0, "level %d: all entries well-formed and distinct" % lv)
		check(bad_unique == 0, "level %d: every puzzle has exactly one solution" % lv)
		check(bad_grade == 0, "level %d: every puzzle grades as level %d" % [lv, lv])
		print("level %d: %d puzzles, avg %.1f clues" % [lv, pool.size(), float(clues) / pool.size()])
	print("pool_check: %d puzzles verified in %d ms" % [total, Time.get_ticks_msec() - t0])
	print("pool_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
