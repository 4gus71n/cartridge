class_name Board
extends RefCounted
## Play state for one Puzzle: entered letters, cursor + direction, check /
## reveal marks and counters, timer. No scene dependency (fully testable).

var puzzle: Puzzle
## Entered letter per cell ("" = empty or block).
var letters: Array[String] = []
## Cells filled by "reveal" (locked, drawn in the reveal colour).
var revealed: Array[bool] = []
## Cells marked wrong by a check (cleared when the letter changes).
var wrong: Array[bool] = []
var cursor := 0
var dir := Puzzle.ACROSS
var elapsed := 0.0
var checks := 0
var reveals := 0
var solved := false


func _init(p: Puzzle) -> void:
	puzzle = p
	var n := p.cell_count()
	letters.resize(n)
	letters.fill("")
	revealed.resize(n)
	revealed.fill(false)
	wrong.resize(n)
	wrong.fill(false)
	cursor = p.white_cells()[0]
	dir = Puzzle.ACROSS if p.across_of[cursor] >= 0 else Puzzle.DOWN


# --- selection -------------------------------------------------------------

func current_entry() -> int:
	return puzzle.entry_at(cursor, dir)


func current_clue() -> Dictionary:
	return puzzle.entries[current_entry()]


## Tap on a cell: select it; tapping the selected cell toggles direction.
func select_cell(i: int) -> void:
	if i < 0 or i >= puzzle.cell_count() or puzzle.is_block(i):
		return
	if i == cursor:
		toggle_dir()
		return
	cursor = i
	if puzzle.entry_at(i, dir) < 0:
		dir = 1 - dir


func toggle_dir() -> void:
	if puzzle.entry_at(cursor, 1 - dir) >= 0:
		dir = 1 - dir


## Jump to entry `k` (index into puzzle.entries): first empty cell, else first.
func go_entry(k: int) -> void:
	var e: Dictionary = puzzle.entries[k]
	dir = e.dir
	cursor = e.cells[0]
	for i in e.cells:
		if letters[i] == "":
			cursor = i
			return


func _entry_full(k: int) -> bool:
	for i in puzzle.entries[k].cells:
		if letters[i] == "":
			return false
	return true


## Next / previous clue (step = +1 / -1), skipping full entries unless every
## entry is full.
func step_entry(step: int) -> void:
	var n := puzzle.entries.size()
	var all_full := is_full()
	var k := current_entry()
	for t in n:
		k = posmod(k + step, n)
		if all_full or not _entry_full(k):
			go_entry(k)
			return


func next_entry() -> void:
	step_entry(1)


func prev_entry() -> void:
	step_entry(-1)


# --- typing ----------------------------------------------------------------

## Types `ch` at the cursor and auto-advances. Revealed cells are kept.
func type_letter(ch: String) -> void:
	if solved:
		return
	ch = ch.to_upper()
	if not revealed[cursor]:
		if letters[cursor] != ch:
			wrong[cursor] = false
		letters[cursor] = ch
	_advance()


func _advance() -> void:
	var k := current_entry()
	var cells: Array = puzzle.entries[k].cells
	var pos := cells.find(cursor)
	# Next empty cell after the cursor in this entry (wrapping round).
	for s in range(1, cells.size()):
		var c: int = cells[(pos + s) % cells.size()]
		if letters[c] == "":
			cursor = c
			return
	if pos < cells.size() - 1:
		cursor = cells[pos + 1]
	elif not is_full():
		next_entry()


## Backspace: clear this cell, or step back and clear the previous one.
func backspace() -> void:
	if solved:
		return
	if letters[cursor] != "" and not revealed[cursor]:
		_clear(cursor)
		return
	var k := current_entry()
	var cells: Array = puzzle.entries[k].cells
	var pos := cells.find(cursor)
	if pos > 0:
		cursor = cells[pos - 1]
	else:
		var pk := posmod(k - 1, puzzle.entries.size())
		dir = puzzle.entries[pk].dir
		cursor = puzzle.entries[pk].cells[-1]
	if not revealed[cursor]:
		_clear(cursor)


func _clear(i: int) -> void:
	letters[i] = ""
	wrong[i] = false


# --- check / reveal ---------------------------------------------------------

func _cells_for(word: bool) -> Array:
	return puzzle.entries[current_entry()].cells if word else [cursor]


## Marks wrong letters in the cell / current word. Returns how many are wrong.
func check(word: bool) -> int:
	checks += 1
	var bad := 0
	for i in _cells_for(word):
		if letters[i] != "" and letters[i] != puzzle.solution[i]:
			wrong[i] = true
			bad += 1
	return bad


## Fills in the solution for the cell / current word.
func reveal(word: bool) -> void:
	reveals += 1
	for i in _cells_for(word):
		if letters[i] != puzzle.solution[i]:
			letters[i] = puzzle.solution[i]
			revealed[i] = true
		wrong[i] = false


# --- state -----------------------------------------------------------------

func is_full() -> bool:
	for i in puzzle.cell_count():
		if not puzzle.is_block(i) and letters[i] == "":
			return false
	return true


func is_correct() -> bool:
	for i in puzzle.cell_count():
		if letters[i] != puzzle.solution[i]:
			return false
	return true


## Call after every change. Returns true the moment the puzzle becomes solved.
func update_solved() -> bool:
	if not solved and is_correct():
		solved = true
		return true
	return false


func filled_count() -> int:
	var n := 0
	for i in puzzle.cell_count():
		if letters[i] != "":
			n += 1
	return n


func to_dict() -> Dictionary:
	var s := ""
	var rev: Array[int] = []
	var bad: Array[int] = []
	for i in puzzle.cell_count():
		s += letters[i] if letters[i] != "" else "."
		if revealed[i]:
			rev.append(i)
		if wrong[i]:
			bad.append(i)
	return {"letters": s, "revealed": rev, "wrong": bad, "cursor": cursor, "dir": dir,
		"elapsed": elapsed, "checks": checks, "reveals": reveals, "solved": solved}


static func from_dict(p: Puzzle, d: Dictionary) -> Board:
	var b := Board.new(p)
	var s := str(d.get("letters", ""))
	if s.length() == p.cell_count():
		for i in p.cell_count():
			var ch := s.substr(i, 1)
			b.letters[i] = "" if ch == "." or p.is_block(i) else ch
	for i in d.get("revealed", []):
		if int(i) < p.cell_count():
			b.revealed[int(i)] = true
	for i in d.get("wrong", []):
		if int(i) < p.cell_count():
			b.wrong[int(i)] = true
	var c := int(d.get("cursor", b.cursor))
	if c >= 0 and c < p.cell_count() and not p.is_block(c):
		b.cursor = c
	b.dir = clampi(int(d.get("dir", b.dir)), 0, 1)
	if p.entry_at(b.cursor, b.dir) < 0:
		b.dir = 1 - b.dir
	b.elapsed = float(d.get("elapsed", 0.0))
	b.checks = int(d.get("checks", 0))
	b.reveals = int(d.get("reveals", 0))
	b.solved = bool(d.get("solved", false)) and b.is_correct()
	return b
