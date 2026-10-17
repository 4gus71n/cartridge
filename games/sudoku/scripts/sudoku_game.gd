class_name SudokuGame
extends RefCounted
## One sudoku session: givens, the player's digits and pencil marks, a
## multi-level undo stack, hints, timer and win detection. No scene
## dependency, so it is fully unit-testable and serialisable.

enum { EASY = 1, MEDIUM = 2, HARD = 3 }

var level := MEDIUM
var daily_day := -1 ## day number (days since epoch) for the daily puzzle, -1 otherwise
var puzzle := PackedInt32Array() ## givens (0 = empty)
var solution := PackedInt32Array()
var values := PackedInt32Array() ## current digits (givens included)
var notes := PackedInt32Array() ## pencil-mark bitmasks (bits 1..9)
var hinted := PackedByteArray() ## 1 = digit revealed by a hint (locked)
var elapsed := 0.0
var hints_used := 0
var mistakes := 0 ## wrong digits entered (counted whether or not checking is on)
var won := false
## Undo stack: each entry is an Array of [cell, old_value, old_notes, old_hinted].
var _undo: Array = []


static func create(givens: PackedInt32Array, lv: int, day := -1) -> SudokuGame:
	var g := SudokuGame.new()
	g.level = lv
	g.daily_day = day
	g.puzzle = givens.duplicate()
	g.solution = SudokuSolver.solve(givens)
	g.values = givens.duplicate()
	g.notes = PackedInt32Array()
	g.notes.resize(81)
	g.hinted = PackedByteArray()
	g.hinted.resize(81)
	return g


## A pooled puzzle of `lv`, disguised by a random validity-preserving shuffle.
static func from_pool(lv: int, seed_value: int, day := -1) -> SudokuGame:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var pool: Array = pool_for(lv)
	var src: String = pool[rng.randi_range(0, pool.size() - 1)]
	var t := SudokuGenerator.random_transform(rng)
	return create(SudokuGenerator.apply_transform(SudokuGrid.parse(src), t), lv, day)


static func pool_for(lv: int) -> Array:
	match lv:
		EASY:
			return PuzzlePool.EASY
		HARD:
			return PuzzlePool.HARD
	return PuzzlePool.MEDIUM


## The daily puzzle: same for everyone on a given calendar day (Medium).
static func daily(day: int) -> SudokuGame:
	return from_pool(MEDIUM, 7919 * day + 104729, day)


## Days since 1970-01-01 for a "YYYY-MM-DD" date string.
static func day_number(date: String) -> int:
	return int(Time.get_unix_time_from_datetime_string(date + "T12:00:00") / 86400)


static func today() -> int:
	return day_number(Time.get_date_string_from_system(false))


# --- queries ----------------------------------------------------------------

func is_given(i: int) -> bool:
	return puzzle[i] != 0


func is_locked(i: int) -> bool:
	return puzzle[i] != 0 or hinted[i] == 1


func is_wrong(i: int) -> bool:
	return values[i] != 0 and values[i] != solution[i]


## Digit `d` still to place: 9 minus the cells currently holding it.
func remaining(d: int) -> int:
	var n := 9
	for v in values:
		if v == d:
			n -= 1
	return maxi(n, 0)


## Cells that clash with `i` under the sudoku rules (same digit in a peer).
func conflicts(i: int) -> bool:
	var v: int = values[i]
	if v == 0:
		return false
	for p in SudokuGrid.PEERS[i]:
		if values[p] == v:
			return true
	return false


func filled_count() -> int:
	var n := 0
	for v in values:
		if v != 0:
			n += 1
	return n


func is_full() -> bool:
	return filled_count() == 81


func can_undo() -> bool:
	return not _undo.is_empty()


func undo_depth() -> int:
	return _undo.size()


# --- actions (all return true when something changed) -----------------------

## Writes digit `d` (1..9) into cell `i`; clears that digit from peers' notes.
func set_value(i: int, d: int) -> bool:
	if won or is_locked(i) or d < 1 or d > 9 or values[i] == d:
		return false
	var rec: Array = [_snap(i)]
	values[i] = d
	notes[i] = 0
	var bit := 1 << d
	for p in SudokuGrid.PEERS[i]:
		if notes[p] & bit:
			rec.append(_snap(p))
			notes[p] &= ~bit
	_undo.append(rec)
	if d != solution[i]:
		mistakes += 1
	_check_win()
	return true


## Toggles pencil mark `d` in an empty, unlocked cell.
func toggle_note(i: int, d: int) -> bool:
	if won or is_locked(i) or values[i] != 0 or d < 1 or d > 9:
		return false
	_undo.append([_snap(i)])
	notes[i] ^= 1 << d
	return true


## Clears the digit (or, if empty, the notes) of an unlocked cell.
func erase(i: int) -> bool:
	if won or is_locked(i) or (values[i] == 0 and notes[i] == 0):
		return false
	_undo.append([_snap(i)])
	if values[i] != 0:
		values[i] = 0
	else:
		notes[i] = 0
	return true


## Reverts the last action. Returns the main cell it touched, or -1.
func undo() -> int:
	if won or _undo.is_empty():
		return -1
	var rec: Array = _undo.pop_back()
	for k in range(rec.size() - 1, -1, -1):
		var s: Array = rec[k]
		values[s[0]] = s[1]
		notes[s[0]] = s[2]
		hinted[s[0]] = s[3]
	return rec[0][0]


## Reveals one correct digit (counted). Prefers `prefer` when it is open or
## wrong, otherwise the empty cell with the fewest candidates. Returns the cell.
func hint(prefer := -1) -> int:
	if won:
		return -1
	var target := -1
	if prefer >= 0 and not is_locked(prefer) and values[prefer] != solution[prefer]:
		target = prefer
	else:
		var best := 99
		for i in 81:
			if is_locked(i) or values[i] == solution[i]:
				continue
			var n := 9 if values[i] != 0 else SudokuGrid.POP[_candidates(i)]
			if n < best:
				best = n
				target = i
	if target < 0:
		return -1
	var rec: Array = [_snap(target)]
	var d: int = solution[target]
	values[target] = d
	notes[target] = 0
	hinted[target] = 1
	var bit := 1 << d
	for p in SudokuGrid.PEERS[target]:
		if notes[p] & bit:
			rec.append(_snap(p))
			notes[p] &= ~bit
	_undo.append(rec)
	hints_used += 1
	_check_win()
	return target


## Fills every empty cell's pencil marks with its legal candidates (undoable).
func auto_notes() -> bool:
	var rec: Array = []
	for i in 81:
		if values[i] == 0:
			var m := _candidates(i)
			if notes[i] != m:
				rec.append(_snap(i))
				notes[i] = m
	if rec.is_empty():
		return false
	_undo.append(rec)
	return true


func tick(delta: float) -> void:
	if not won:
		elapsed += delta


# --- persistence --------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"v": 1,
		"level": level,
		"daily_day": daily_day,
		"puzzle": SudokuGrid.stringify(puzzle),
		"values": SudokuGrid.stringify(values),
		"notes": Array(notes),
		"hinted": Array(hinted),
		"elapsed": elapsed,
		"hints": hints_used,
		"mistakes": mistakes,
		"undo": _undo,
	}


static func from_dict(d: Dictionary) -> SudokuGame:
	if int(d.get("v", 0)) != 1:
		return null
	var givens := SudokuGrid.parse(str(d.get("puzzle", "")))
	if SudokuGrid.count_givens(givens) < 17 or not SudokuSolver.has_unique_solution(givens):
		return null
	var g := create(givens, int(d.get("level", MEDIUM)), int(d.get("daily_day", -1)))
	var vals := SudokuGrid.parse(str(d.get("values", "")))
	var ns: Array = d.get("notes", [])
	var hs: Array = d.get("hinted", [])
	for i in 81:
		if g.puzzle[i] == 0:
			g.values[i] = vals[i]
		if i < ns.size():
			g.notes[i] = int(ns[i]) & SudokuGrid.ALL
		if i < hs.size():
			g.hinted[i] = 1 if int(hs[i]) == 1 and g.puzzle[i] == 0 else 0
	g.elapsed = float(d.get("elapsed", 0.0))
	g.hints_used = int(d.get("hints", 0))
	g.mistakes = int(d.get("mistakes", 0))
	for rec in d.get("undo", []):
		var clean: Array = []
		for s in rec:
			clean.append([int(s[0]), int(s[1]), int(s[2]), int(s[3])])
		g._undo.append(clean)
	g._check_win()
	return g


# --- internals ----------------------------------------------------------------

func _snap(i: int) -> Array:
	return [i, values[i], notes[i], hinted[i]]


func _candidates(i: int) -> int:
	var m := SudokuGrid.ALL
	for p in SudokuGrid.PEERS[i]:
		if values[p] != 0:
			m &= ~(1 << values[p])
	return m


func _check_win() -> void:
	won = values == solution
