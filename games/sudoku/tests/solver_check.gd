extends SceneTree
## Exact solver + generator transforms.
## godot --headless --path . --script tests/solver_check.gd

const P := "53..7....6..195....98....6.8...6...34..8.3..17...2...6.6....28....419..5....8..79"
const S := "534678912672195348198342567859761423426853791713924856961537284287419635345286179"

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	var p := SudokuGrid.parse(P)
	check(SudokuGrid.count_givens(p) == 30, "parse counts givens")
	check(SudokuGrid.stringify(p) == P, "stringify round-trips")
	check(SudokuSolver.count_solutions(p, 2) == 1, "classic puzzle is unique")
	var sol := SudokuSolver.solve(p)
	check(SudokuGrid.stringify(sol) == S, "solver finds the known solution")
	check(SudokuGrid.is_solved_grid(sol), "solution is a valid grid")
	# Removing clues breaks uniqueness.
	var loose := p.duplicate()
	for i in 81:
		if i % 2 == 0:
			loose[i] = 0
	check(SudokuSolver.count_solutions(loose, 2) == 2, "under-constrained grid has many solutions")
	var empty := PackedInt32Array()
	empty.resize(81)
	check(SudokuSolver.count_solutions(empty, 5) == 5, "empty grid hits the limit")
	# Rule conflict among givens -> 0.
	var bad := p.duplicate()
	bad[2] = 5 # row 0 already has a 5
	check(SudokuSolver.count_solutions(bad, 2) == 0, "conflicting givens have no solution")
	check(not SudokuGrid.is_consistent(bad), "is_consistent spots the clash")
	check(SudokuSolver.solve(bad).is_empty(), "solve returns empty for unsolvable")
	check(SudokuSolver.count_solutions(PackedInt32Array([1, 2]), 2) == 0, "wrong size rejected")
	# Geometry tables.
	check(SudokuGrid.PEERS[0].size() == 20 and SudokuGrid.PEERS[40].size() == 20, "20 peers per cell")
	check(SudokuGrid.box(80) == 8 and SudokuGrid.box(30) == 4, "box index")
	check(SudokuGrid.is_peer(0, 80) == false and SudokuGrid.is_peer(0, 20), "peer flags")
	# Random completions are valid and seed-deterministic.
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var g1 := SudokuGenerator.full_grid(rng)
	rng.seed = 42
	var g2 := SudokuGenerator.full_grid(rng)
	check(SudokuGrid.is_solved_grid(g1), "random full grid is valid")
	check(g1 == g2, "full grid is deterministic per seed")
	# Isomorphic transforms keep validity and uniqueness.
	for k in 20:
		var t := SudokuGenerator.random_transform(rng)
		var tp := SudokuGenerator.apply_transform(p, t)
		var ts := SudokuGenerator.apply_transform(SudokuGrid.parse(S), t)
		check(SudokuGrid.is_solved_grid(ts), "transformed solution valid (%d)" % k)
		check(SudokuSolver.count_solutions(tp, 2) == 1, "transformed puzzle unique (%d)" % k)
		check(SudokuSolver.solve(tp) == ts, "transform commutes with solving (%d)" % k)
	# Generator: symmetric, unique.
	var r := SudokuGenerator.make_puzzle(rng)
	var gp: PackedInt32Array = r.puzzle
	check(SudokuSolver.count_solutions(gp, 2) == 1, "generated puzzle is unique")
	var sym := true
	for i in 81:
		if (gp[i] == 0) != (gp[80 - i] == 0):
			sym = false
	check(sym, "generated puzzle is rotationally symmetric")
	print("solver_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
