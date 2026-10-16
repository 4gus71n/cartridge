class_name SudokuSolver
extends RefCounted
## Exact backtracking solver (bitmasks + most-constrained-cell first).
## Used to prove uniqueness and to fill random complete grids.

const ALL := 0x3FE

var _g := PackedInt32Array()
var _rows := PackedInt32Array()
var _cols := PackedInt32Array()
var _boxes := PackedInt32Array()
var _pop: PackedInt32Array
var _count := 0
var _limit := 2
var _solution := PackedInt32Array()
var _rng: RandomNumberGenerator = null
## Search nodes visited (exposed for benchmarks).
var nodes := 0


## Number of solutions, stopping once `limit` is reached (2 = uniqueness test).
## Grids with a rule conflict among the givens return 0.
static func count_solutions(grid: PackedInt32Array, limit := 2) -> int:
	var s := SudokuSolver.new()
	return s.run(grid, limit)


static func has_unique_solution(grid: PackedInt32Array) -> bool:
	return count_solutions(grid, 2) == 1


## First solution found, or an empty array when unsolvable.
static func solve(grid: PackedInt32Array) -> PackedInt32Array:
	var s := SudokuSolver.new()
	s.run(grid, 1)
	return s._solution


## A uniformly shuffled search order produces a random completion of `grid`
## (an empty grid gives a random full sudoku).
static func random_completion(grid: PackedInt32Array, rng: RandomNumberGenerator) -> PackedInt32Array:
	var s := SudokuSolver.new()
	s._rng = rng
	s.run(grid, 1)
	return s._solution


func run(grid: PackedInt32Array, limit: int) -> int:
	_pop = SudokuGrid.POP
	_g = grid.duplicate()
	_rows.resize(9)
	_cols.resize(9)
	_boxes.resize(9)
	_rows.fill(0)
	_cols.fill(0)
	_boxes.fill(0)
	_count = 0
	_limit = limit
	_solution = PackedInt32Array()
	if _g.size() != 81:
		return 0
	for i in 81:
		var d: int = _g[i]
		if d == 0:
			continue
		if d < 0 or d > 9:
			return 0
		var bit := 1 << d
		var r := i / 9
		var c := i % 9
		var b := (i / 27) * 3 + c / 3
		if (_rows[r] | _cols[c] | _boxes[b]) & bit:
			return 0
		_rows[r] |= bit
		_cols[c] |= bit
		_boxes[b] |= bit
	_search()
	return _count


func _search() -> void:
	nodes += 1
	var best := -1
	var best_mask := 0
	var best_n := 10
	for i in 81:
		if _g[i] != 0:
			continue
		var c := i % 9
		var m := ALL & ~(_rows[i / 9] | _cols[c] | _boxes[(i / 27) * 3 + c / 3])
		var n: int = _pop[m]
		if n < best_n:
			best = i
			best_mask = m
			best_n = n
			if n <= 1:
				break
	if best < 0:
		_count += 1
		if _solution.is_empty():
			_solution = _g.duplicate()
		return
	if best_n == 0:
		return
	var r := best / 9
	var cc := best % 9
	var b := (best / 27) * 3 + cc / 3
	var digits := []
	for d in range(1, 10):
		if best_mask & (1 << d):
			digits.append(d)
	if _rng != null:
		for k in range(digits.size() - 1, 0, -1):
			var j := _rng.randi_range(0, k)
			var t = digits[k]
			digits[k] = digits[j]
			digits[j] = t
	for d in digits:
		var bit := 1 << d
		_g[best] = d
		_rows[r] |= bit
		_cols[cc] |= bit
		_boxes[b] |= bit
		_search()
		_g[best] = 0
		_rows[r] &= ~bit
		_cols[cc] &= ~bit
		_boxes[b] &= ~bit
		if _count >= _limit:
			return
