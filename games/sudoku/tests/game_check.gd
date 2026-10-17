extends SceneTree
## SudokuGame session logic + Settings persistence: entry, pencil marks,
## multi-level undo, hints, remaining counts, win detection, save/load,
## records, daily seed + streak.
## godot --headless --path . --script tests/game_check.gd

const P := "53..7....6..195....98....6.8...6...34..8.3..17...2...6.6....28....419..5....8..79"
const TEST_PATH := "user://game_check_test.cfg"

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	_entry_and_notes()
	_undo()
	_hints()
	_win()
	_save_load()
	_pool_and_daily()
	_settings()
	print("game_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _entry_and_notes() -> void:
	var g := SudokuGame.create(SudokuGrid.parse(P), SudokuGame.EASY)
	check(g.solution.size() == 81 and SudokuGrid.is_solved_grid(g.solution), "solution computed")
	check(g.is_given(0) and g.is_locked(0), "given is locked")
	check(not g.set_value(0, 1), "cannot overwrite a given")
	check(not g.toggle_note(0, 1), "cannot pencil a given")
	check(g.remaining(5) == 9 - 3, "remaining counts givens (5 appears 3x)")
	# Cell 2 (row 0, col 2) solution is 4.
	check(g.set_value(2, 4), "enter a digit")
	check(g.values[2] == 4 and not g.is_wrong(2) and g.mistakes == 0, "correct digit, no mistake")
	check(not g.set_value(2, 4), "same digit again is a no-op")
	check(g.set_value(2, 1), "overwrite with a wrong digit")
	check(g.is_wrong(2) and g.mistakes == 1, "wrong digit flagged + counted")
	check(g.erase(2) and g.values[2] == 0, "erase digit")
	check(not g.erase(2), "erase on empty cell without notes is a no-op")
	# Pencil marks.
	check(g.toggle_note(3, 2) and g.toggle_note(3, 6) and g.notes[3] == (1 << 2) | (1 << 6), "two pencil marks")
	check(g.toggle_note(3, 6) and g.notes[3] == 1 << 2, "toggle removes a mark")
	check(g.toggle_note(6, 6) and g.toggle_note(21, 6), "marks in peers (same row/box) of cell 3")
	var far := 72 # row 8, col 0: not a peer of cell 3
	check(g.values[far] == 0, "far cell empty")
	g.toggle_note(far, 6)
	g.set_value(3, 6) # solution digit there is 6
	check(g.notes[3] == 0, "placing a digit clears own marks")
	check(g.notes[6] & (1 << 6) == 0 and g.notes[21] & (1 << 6) == 0, "placing clears that mark from peers")
	check(g.notes[far] & (1 << 6) != 0, "non-peer marks untouched")
	check(not g.toggle_note(3, 1), "cannot pencil a filled cell")
	check(g.erase(far) and g.notes[far] == 0, "erase clears notes of an empty cell")
	check(g.auto_notes(), "auto notes fills candidates")
	check(g.notes[2] == (1 << 1) | (1 << 2) | (1 << 4), "candidates of cell 2 = {1,2,4}")
	check(not g.auto_notes(), "auto notes twice is a no-op")


func _undo() -> void:
	var g := SudokuGame.create(SudokuGrid.parse(P), SudokuGame.EASY)
	var start := g.values.duplicate()
	check(not g.can_undo() and g.undo() == -1, "nothing to undo initially")
	g.toggle_note(2, 4)
	g.toggle_note(11, 4) # peer (same box)
	g.toggle_note(11, 2)
	g.set_value(2, 4) # clears mark 4 from cell 11
	g.set_value(5, 9) # wrong (solution 8)
	g.erase(5)
	check(g.undo_depth() == 6, "six undo steps recorded")
	check(g.undo() == 5 and g.values[5] == 9, "undo erase restores digit")
	check(g.undo() == 5 and g.values[5] == 0, "undo wrong entry")
	check(g.undo() == 2 and g.values[2] == 0 and g.notes[2] == 1 << 4, "undo placement restores own notes")
	check(g.notes[11] == (1 << 4) | (1 << 2), "undo placement restores peer notes")
	g.undo()
	g.undo()
	check(g.undo() == 2 and g.notes[2] == 0, "undo first note")
	check(g.values == start and not g.can_undo(), "fully back to start")
	check(g.mistakes == 1, "mistake count is not refunded by undo")


func _hints() -> void:
	var g := SudokuGame.create(SudokuGrid.parse(P), SudokuGame.MEDIUM)
	g.set_value(2, 1) # wrong
	var c := g.hint(2)
	check(c == 2 and g.values[2] == 4 and g.hinted[2] == 1, "hint fixes the preferred wrong cell")
	check(g.is_locked(2) and not g.set_value(2, 7) and not g.erase(2), "hinted cell is locked")
	check(g.hints_used == 1, "hint counted")
	var c2 := g.hint(0) # given -> picks another cell
	check(c2 >= 0 and c2 != 0 and g.values[c2] == g.solution[c2], "hint on a given falls back to best cell")
	check(g.undo() == c2 and g.values[c2] == 0 and g.hinted[c2] == 0, "hint is undoable")
	check(g.hints_used == 2, "undo does not refund hints")


func _win() -> void:
	var g := SudokuGame.create(SudokuGrid.parse(P), SudokuGame.EASY)
	var empties := []
	for i in 81:
		if g.values[i] == 0:
			empties.append(i)
	# Fill all but the last correctly, the last one wrong: full but not won.
	for k in empties.size():
		var i: int = empties[k]
		var d: int = g.solution[i]
		if k == empties.size() - 1:
			d = d % 9 + 1
		g.set_value(i, d)
	check(g.is_full() and not g.won, "full board with a wrong digit is not a win")
	g.tick(12.5)
	var last: int = empties[-1]
	g.set_value(last, g.solution[last])
	check(g.won, "correct last digit wins")
	check(not g.set_value(last, 1) and g.undo() == -1 and g.hint() == -1, "board frozen after win")
	var t := g.elapsed
	g.tick(5.0)
	check(g.elapsed == t, "timer stops after win")


func _save_load() -> void:
	var g := SudokuGame.from_pool(SudokuGame.HARD, 99, 20000)
	var empties := []
	for i in 81:
		if g.values[i] == 0:
			empties.append(i)
	g.set_value(empties[0], g.solution[empties[0]])
	g.set_value(empties[1], g.solution[empties[1]] % 9 + 1)
	g.toggle_note(empties[2], 3)
	g.toggle_note(empties[2], 7)
	g.hint(empties[3])
	g.tick(83.25)
	var d := g.to_dict()
	var restored = JSON.parse_string(JSON.stringify(d)) # simulate the ConfigFile/JSON trip
	var h := SudokuGame.from_dict(restored)
	check(h != null, "save round-trips")
	if h == null:
		return
	check(h.puzzle == g.puzzle and h.values == g.values and h.notes == g.notes and h.hinted == g.hinted, "grid, notes, hints restored")
	check(h.level == SudokuGame.HARD and h.daily_day == 20000, "level + daily day restored")
	check(is_equal_approx(h.elapsed, 83.25) and h.hints_used == 1 and h.mistakes == 1, "timer + counters restored")
	check(h.undo_depth() == g.undo_depth(), "undo stack restored")
	check(h.undo() == empties[3] and h.values[empties[3]] == 0, "restored undo works")
	check(h.is_locked(empties[3]) == false, "undone hint unlocks the cell")
	check(SudokuGame.from_dict({}) == null, "empty dict rejected")
	var broken := d.duplicate()
	broken.puzzle = "11" + str(d.puzzle).substr(2)
	check(SudokuGame.from_dict(broken) == null, "non-unique / corrupt puzzle rejected")


func _pool_and_daily() -> void:
	var a := SudokuGame.from_pool(SudokuGame.EASY, 5)
	var b := SudokuGame.from_pool(SudokuGame.EASY, 5)
	var c := SudokuGame.from_pool(SudokuGame.EASY, 6)
	check(a.puzzle == b.puzzle, "pool pick deterministic per seed")
	check(a.puzzle != c.puzzle, "different seed, different puzzle")
	check(SudokuSolver.has_unique_solution(a.puzzle) and SudokuGrader.grade(a.puzzle) == SudokuGame.EASY, "disguised pool puzzle keeps uniqueness + grade")
	var day := SudokuGame.day_number("2026-10-17")
	check(day == SudokuGame.day_number("2026-10-16") + 1, "consecutive dates -> consecutive day numbers")
	check(SudokuGame.day_number("2027-01-01") - day == 76, "day numbers count calendar days")
	check(SudokuGame.daily(day).puzzle == SudokuGame.daily(day).puzzle, "daily is the same all day")
	check(SudokuGame.daily(day).puzzle != SudokuGame.daily(day + 1).puzzle, "daily changes tomorrow")
	check(SudokuGame.daily(day).daily_day == day and SudokuGame.daily(day).level == SudokuGame.MEDIUM, "daily is Medium and tagged")
	check(SudokuGame.today() > 20000, "today() is a plausible day number")


func _settings() -> void:
	var st: Node = load("res://scripts/settings.gd").new()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	st.load_from(TEST_PATH)
	check(st.best_times[1] == 0.0 and st.streak == 0 and st.saved_game.is_empty(), "fresh settings")
	check(st.record_win(1, 300.0), "first win is a record")
	check(not st.record_win(1, 320.0), "slower win is not a record")
	check(st.record_win(1, 250.0) and st.best_times[1] == 250.0, "faster win is a record")
	check(st.solved[1] == 3, "solved counter")
	st.record_win(2, 600.0, 100)
	st.record_win(2, 600.0, 101)
	check(st.streak == 2 and st.daily_done(101) and st.current_streak(102) == 2, "consecutive dailies build a streak")
	check(st.current_streak(103) == 0, "missing a day breaks the shown streak")
	st.record_win(2, 600.0, 101)
	check(st.streak == 2, "replaying the same daily doesn't double count")
	st.record_win(2, 600.0, 105)
	check(st.streak == 1 and st.best_streak == 2, "gap restarts the streak, best kept")
	var g := SudokuGame.from_pool(SudokuGame.MEDIUM, 3)
	g.set_value(0 if g.values[0] == 0 else g.values.find(0), 5)
	st.store_game(g.to_dict())
	st.set_mistake_check(false)
	st.set_language("es")
	var st2: Node = load("res://scripts/settings.gd").new()
	st2.load_from(TEST_PATH)
	check(st2.best_times[1] == 250.0 and st2.best_times[2] == 600.0, "best times persisted")
	check(st2.streak == 1 and st2.best_streak == 2 and st2.last_daily == 105, "streak persisted")
	check(not st2.mistake_check and st2.language == "es", "toggles persisted")
	var h := SudokuGame.from_dict(st2.saved_game)
	check(h != null and h.values == g.values, "in-progress game persisted")
	st2.clear_game()
	st2.load_from(TEST_PATH)
	check(st2.saved_game.is_empty(), "clear_game removes the save")
	TranslationServer.set_locale("en")
	st.free()
	st2.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
