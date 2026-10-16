class_name SudokuGenerator
extends RefCounted
## Builds unique-solution puzzles and applies validity-preserving shuffles.
## Heavy generation runs offline (tools/gen_pool.gd) to fill PuzzlePool; at
## runtime we only pick a pooled puzzle and shuffle it (digits, rows within
## bands, bands, columns, stacks, transpose), which keeps uniqueness and the
## technique-based grade intact.


static func shuffled(arr: Array, rng: RandomNumberGenerator) -> Array:
	var a := arr.duplicate()
	for k in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var t = a[k]
		a[k] = a[j]
		a[j] = t
	return a


static func full_grid(rng: RandomNumberGenerator) -> PackedInt32Array:
	var empty := PackedInt32Array()
	empty.resize(81)
	return SudokuSolver.random_completion(empty, rng)


## Rotationally symmetric puzzle, minimal w.r.t. symmetric pair removal.
## Returns {puzzle, solution} (PackedInt32Array each).
static func make_puzzle(rng: RandomNumberGenerator) -> Dictionary:
	var sol := full_grid(rng)
	var p := sol.duplicate()
	var order := []
	for i in 41:
		order.append(i)
	order = shuffled(order, rng)
	for i in order:
		var j: int = 80 - i
		var a: int = p[i]
		var b: int = p[j]
		p[i] = 0
		p[j] = 0
		if SudokuSolver.count_solutions(p, 2) != 1:
			p[i] = a
			p[j] = b
	return {"puzzle": p, "solution": sol}


## Adds clues from the solution (symmetric pairs) until `target` givens,
## keeping the grade equal to `level`. Extra clues never break uniqueness.
static func add_clues(puzzle: PackedInt32Array, solution: PackedInt32Array, target: int,
		level: int, rng: RandomNumberGenerator) -> PackedInt32Array:
	var p := puzzle.duplicate()
	var empties := []
	for i in 41:
		if p[i] == 0:
			empties.append(i)
	empties = shuffled(empties, rng)
	for i in empties:
		if SudokuGrid.count_givens(p) >= target:
			break
		var j: int = 80 - i
		p[i] = solution[i]
		p[j] = solution[j]
		if SudokuGrader.grade(p) != level:
			p[i] = 0
			p[j] = 0
	return p


## Random isomorphism: {digits: map old->new (index 0 unused), rows, cols
## (source index for each target line), transpose}.
static func random_transform(rng: RandomNumberGenerator) -> Dictionary:
	var digits := PackedInt32Array([0])
	for d in shuffled([1, 2, 3, 4, 5, 6, 7, 8, 9], rng):
		digits.append(d)
	return {
		"digits": digits,
		"rows": _line_perm(rng),
		"cols": _line_perm(rng),
		"transpose": rng.randi_range(0, 1) == 1,
	}


static func _line_perm(rng: RandomNumberGenerator) -> PackedInt32Array:
	var out := PackedInt32Array()
	for band in shuffled([0, 1, 2], rng):
		for inner in shuffled([0, 1, 2], rng):
			out.append(band * 3 + inner)
	return out


static func apply_transform(g: PackedInt32Array, t: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(81)
	var rows: PackedInt32Array = t.rows
	var cols: PackedInt32Array = t.cols
	var digits: PackedInt32Array = t.digits
	for r in 9:
		for c in 9:
			var sr: int = rows[r]
			var sc: int = cols[c]
			var v: int = g[sc * 9 + sr] if t.transpose else g[sr * 9 + sc]
			out[r * 9 + c] = digits[v] if v > 0 else 0
	return out
