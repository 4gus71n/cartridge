extends SceneTree
## Board logic: numbering, selection / direction toggling, auto-advance,
## backspace, clue navigation, check / reveal counters, completion and the
## save/load round trip, plus the Settings records store.

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


## 5x5 with two corner blocks:
## #CATS / AREAS / TONER / ERODE / SEND#  (columns need not be words here)
func _puzzle() -> Puzzle:
	return Puzzle.from_dict({"id": "t-1", "grid": ["#CATS", "AREAS", "TONER", "ERODE", "SEND#"],
		"across": {"1": "a1", "5": "a5", "6": "a6", "7": "a7", "8": "a8"},
		"down": {"1": "d1", "2": "d2", "3": "d3", "4": "d4", "5": "d5"}})


func _initialize() -> void:
	var p := _puzzle()
	# numbering
	check(p.numbers[1] == 1 and p.numbers[5] == 5 and p.numbers[2] == 2 and p.numbers[20] == 8, "numbers placed")
	check(p.entries.size() == 10, "10 entries (%d)" % p.entries.size())
	var a1: Dictionary = p.entries[0]
	check(a1.answer == "CATS" and a1.clue == "a1" and a1.dir == Puzzle.ACROSS, "1 across")
	var d1: Dictionary = p.entries[p.down_of[1]]
	check(d1.answer == "CRORE" and d1.number == 1, "1 down = CRORE (%s)" % d1.answer)
	check(p.entries[p.down_of[5]].answer == "ATES", "5 down")

	var b := Board.new(p)
	check(b.cursor == 1 and b.dir == Puzzle.ACROSS, "starts on first white cell, across")
	# tap selects, tap again toggles
	b.select_cell(7)
	check(b.cursor == 7 and b.dir == Puzzle.ACROSS, "tap selects")
	b.select_cell(7)
	check(b.dir == Puzzle.DOWN, "second tap toggles to down")
	b.select_cell(7)
	check(b.dir == Puzzle.ACROSS, "third tap toggles back")
	b.select_cell(0)
	check(b.cursor == 7, "tapping a block is ignored")
	# cell with only a down entry switches direction automatically: (4,4) is block, (0,0) block
	b.dir = Puzzle.ACROSS
	b.select_cell(5)  # A of AREAS; has across & down
	check(b.dir == Puzzle.ACROSS, "keeps direction when available")
	# typing auto-advances
	b.select_cell(1)
	for ch in "CA":
		b.type_letter(ch)
	check(b.letters[1] == "C" and b.letters[2] == "A" and b.cursor == 3, "typing advances")
	b.type_letter("t")
	check(b.letters[3] == "T", "lowercase becomes uppercase")
	b.type_letter("S")
	check(b.cursor == 5 and b.dir == Puzzle.ACROSS, "full entry jumps to next clue (%d)" % b.cursor)
	# skip filled cells
	b.select_cell(1)
	b.dir = Puzzle.DOWN
	b.letters[11] = "O"
	b.select_cell(6)
	b.type_letter("R")
	check(b.cursor == 16, "advance skips already-filled cells (%d)" % b.cursor)
	# backspace: clears current, then moves back
	b.type_letter("N")
	check(b.cursor == 21, "advance to last cell")
	b.letters[21] = "E"
	b.backspace()
	check(b.letters[21] == "" and b.cursor == 21, "backspace clears the current cell and stays")
	b.backspace()
	check(b.cursor == 16 and b.letters[16] == "", "backspace on an empty cell steps back and clears")
	b.select_cell(1)
	b.dir = Puzzle.ACROSS
	b.letters[1] = ""
	b.backspace()
	check(b.dir == Puzzle.DOWN and b.cursor == p.entries[-1].cells[-1], "backspace at first cell wraps to previous clue's end")
	# clue navigation
	var fresh := Board.new(p)
	fresh.next_entry()
	check(fresh.current_entry() == 1 and fresh.cursor == 5, "next clue")
	fresh.prev_entry()
	fresh.prev_entry()
	check(fresh.current_entry() == p.entries.size() - 1 and fresh.dir == Puzzle.DOWN, "prev clue wraps to last")
	for i in p.entries[0].cells:
		fresh.letters[i] = "X"
	fresh.go_entry(p.entries.size() - 1)
	fresh.next_entry()
	check(fresh.current_entry() == 1, "next clue skips full entries")
	# check / reveal
	var c := Board.new(p)
	c.letters[1] = "C"
	c.letters[2] = "X"
	c.letters[3] = "T"
	c.cursor = 2
	check(c.check(false) == 1 and c.wrong[2] and c.checks == 1, "check letter marks wrong")
	check(c.check(true) == 1 and c.checks == 2 and not c.wrong[1], "check word counts and leaves right letters")
	c.type_letter("Z")
	check(not c.wrong[2] or c.letters[2] == "Z", "retyping clears the wrong mark")
	c.cursor = 2
	c.reveal(false)
	check(c.letters[2] == "A" and c.revealed[2] and c.reveals == 1 and not c.wrong[2], "reveal letter")
	c.type_letter("Q")
	check(c.letters[2] == "A", "revealed letters are locked")
	c.cursor = 6
	c.dir = Puzzle.ACROSS
	c.reveal(true)
	check(c.letters.slice(5, 10) == ["A", "R", "E", "A", "S"] and c.reveals == 2, "reveal word")
	check(not c.revealed[1], "already-right letters are not marked revealed")
	# completion
	var w := Board.new(p)
	for i in p.cell_count():
		if not p.is_block(i):
			w.letters[i] = p.solution[i]
	w.letters[24 - 1] = "X"
	check(w.is_full() and not w.is_correct() and not w.update_solved(), "full but wrong is not solved")
	w.cursor = 23
	w.dir = Puzzle.ACROSS
	w.type_letter("D")
	check(w.update_solved() and w.solved, "last right letter solves")
	check(not w.update_solved(), "solved fires once")
	w.type_letter("Q")
	check(w.letters[23] == "D", "no edits after solving")
	# save / load
	var s := Board.new(p)
	s.select_cell(8)
	s.toggle_dir()
	s.type_letter("A")
	s.letters[12] = "Z"
	s.cursor = 12
	s.check(false)
	s.cursor = 13
	s.reveal(false)
	check(s.wrong[12] and s.revealed[13], "marks set before saving")
	s.elapsed = 42.5
	var d := s.to_dict()
	var copy: Dictionary = JSON.parse_string(JSON.stringify(d))
	var r := Board.from_dict(p, copy)
	check(r.letters == s.letters and r.revealed == s.revealed and r.wrong == s.wrong, "letters + marks round-trip")
	check(r.cursor == s.cursor and r.dir == s.dir and is_equal_approx(r.elapsed, 42.5), "cursor, dir, time round-trip")
	check(r.checks == 1 and r.reveals == 1 and not r.solved, "counters round-trip")
	var junk := Board.from_dict(p, {"letters": "short", "cursor": 0, "dir": 7})
	check(junk.filled_count() == 0 and not p.is_block(junk.cursor), "corrupt save falls back safely")
	# settings records
	var st = load("res://scripts/settings.gd").new()
	var path := OS.get_environment("TMPDIR").path_join("crossword-work/board_check.cfg")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	DirAccess.remove_absolute(path)
	st.path = path
	st.load_settings()
	st.save_progress("t-1", d)
	check(st.record_solve("t-1", 80.0, false) and st.best_time("t-1") == 80.0, "first clean solve is a best")
	check(not st.progress.has("t-1"), "solving clears in-progress state")
	check(not st.record_solve("t-1", 95.0, false) and st.best_time("t-1") == 80.0, "slower is not a best")
	check(st.record_solve("t-1", 60.0, false), "faster is a best")
	check(not st.record_solve("t-2", 10.0, true) and st.is_solved("t-2") and st.best_time("t-2") < 0, "assisted solve: solved, no time")
	st.save_progress("t-3", d)
	var st2 = load("res://scripts/settings.gd").new()
	st2.path = path
	st2.load_settings()
	check(st2.best_time("t-1") == 60.0 and st2.is_solved("t-2"), "records persist")
	check(Board.from_dict(p, st2.progress["t-3"]).letters == s.letters, "progress persists")
	st.free()
	st2.free()
	DirAccess.remove_absolute(path)
	TranslationServer.set_locale("en")
	print("board_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
