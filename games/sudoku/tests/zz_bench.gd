extends SceneTree
func _initialize():
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var t0 := Time.get_ticks_msec()
	var g := SudokuGenerator.full_grid(rng)
	print("full ", Time.get_ticks_msec()-t0, " ", SudokuGrid.stringify(g), " ", SudokuGrid.is_solved_grid(g))
	t0 = Time.get_ticks_msec()
	var p := g.duplicate()
	for i in 30: p[i*2] = 0
	print("count ", SudokuSolver.count_solutions(p, 2), " ", Time.get_ticks_msec()-t0)
	t0 = Time.get_ticks_msec()
	var r := SudokuGenerator.make_puzzle(rng)
	print("make ", Time.get_ticks_msec()-t0, " ", SudokuGrid.stringify(r.puzzle))
	t0 = Time.get_ticks_msec()
	print(SudokuGrader.analyze(r.puzzle))
	print("grade ", Time.get_ticks_msec()-t0)
	quit()
