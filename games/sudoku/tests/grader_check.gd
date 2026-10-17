extends SceneTree
## Human-technique grader: tiers, technique usage, logical solve correctness.
## godot --headless --path . --script tests/grader_check.gd

const TIER2 := ["naked_pair", "hidden_pair", "pointing", "claiming"]
const TIER3 := ["naked_triple", "hidden_triple", "x_wing", "swordfish", "xy_wing"]
## Famously hard puzzle that needs chains/guessing: beyond our Hard tier.
const ESCARGOT := "1....7.9..3..2...8..96..5....53..9...1..8...26....4...3......1..4......7..7...3.."
const CLASSIC := "53..7....6..195....98....6.8...6...34..8.3..17...2...6.6....28....419..5....8..79"

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _uses(tech: Dictionary, names: Array) -> bool:
	for n in names:
		if tech.has(n):
			return true
	return false


func _initialize() -> void:
	var a := SudokuGrader.analyze(SudokuGrid.parse(CLASSIC))
	check(a.level == SudokuGrader.EASY and a.solved, "classic newspaper puzzle is Easy")
	check(SudokuGrid.stringify(a.values) == SudokuGrid.stringify(SudokuSolver.solve(SudokuGrid.parse(CLASSIC))), "logical solve matches exact solver")
	var e := SudokuGrader.analyze(SudokuGrid.parse(ESCARGOT))
	check(e.level == SudokuGrader.EXPERT and not e.solved, "AI Escargot is beyond Hard (got %d)" % e.level)
	# Partial logical progress must never contradict the true solution.
	var esol := SudokuSolver.solve(SudokuGrid.parse(ESCARGOT))
	var ok := true
	for i in 81:
		if e.values[i] != 0 and e.values[i] != esol[i]:
			ok = false
	check(ok, "grader never places a wrong digit")
	# Technique usage per tier, over a sample of each pool.
	var names := {1: "easy", 2: "medium", 3: "hard"}
	for lv in [1, 2, 3]:
		var pool: Array = SudokuGame.pool_for(lv)
		var bad := 0
		for k in range(0, pool.size(), 10):
			var g := SudokuGrid.parse(pool[k])
			var r := SudokuGrader.analyze(g)
			var tech: Dictionary = r.techniques
			var solved_ok: bool = r.solved and r.values == SudokuSolver.solve(g)
			var tier_ok := true
			match lv:
				1:
					tier_ok = not _uses(tech, TIER2) and not _uses(tech, TIER3)
				2:
					tier_ok = _uses(tech, TIER2) and not _uses(tech, TIER3)
				3:
					tier_ok = _uses(tech, TIER3)
			if not solved_ok or not tier_ok:
				bad += 1
				printerr("%s #%d techniques %s" % [names[lv], k, tech])
		check(bad == 0, "%s sample uses the right technique tier" % names[lv])
	# Grade is invariant under sudoku isomorphisms.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for lv in [1, 2, 3]:
		var src := SudokuGrid.parse(SudokuGame.pool_for(lv)[3])
		var t := SudokuGenerator.random_transform(rng)
		check(SudokuGrader.grade(SudokuGenerator.apply_transform(src, t)) == lv, "grade survives transform (level %d)" % lv)
	print("grader_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
