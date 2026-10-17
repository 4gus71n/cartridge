extends SceneTree
## UI bot: boots the real main scene and plays through the same entry points
## the buttons use (real Button.pressed signals and real grid clicks): menu,
## daily puzzle, tap / toggle, clue arrows, custom keyboard typing a whole
## puzzle, wrong-fill toast, check / reveal sheet, completion card, list
## checkmarks + best time, resume after leaving, language switch (Ñ key).

var _pass := 0
var _fail := 0
var main: Control
var path := ""


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	path = OS.get_environment("TMPDIR").path_join("crossword-work/ui_test.cfg")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	DirAccess.remove_absolute(path)
	var settings = root.get_node("Settings")
	settings.path = path
	settings.load_settings()
	settings.set_language("en")
	root.size = Vector2i(720, 1280)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred(settings)


func _frames(n := 2) -> void:
	for i in n:
		await process_frame


func _buttons(n: Node) -> Array:
	var out := []
	for c in n.find_children("*", "Button", true, false):
		if c.is_visible_in_tree():
			out.append(c)
	return out


func _find(n: Node, text: String) -> Button:
	for b in _buttons(n):
		if (b as Button).text.begins_with(text):
			return b
	return null


func _click_cell(i: int) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = main._grid.cell_center(i)
	main._grid._gui_input(ev)


func _type(word: String) -> void:
	for ch in word:
		main._keys[ch].pressed.emit()


func _run(settings) -> void:
	await _frames(3)
	check(main.screen == "menu", "boots to menu")
	for b in _buttons(main._menu):
		check(b.size.y >= 88.0, "menu button '%s' >= 88 px (%.0f)" % [b.text, b.size.y])
	var daily := _find(main._menu, tr("DAILY"))
	check(daily != null, "menu has today's puzzle")
	daily.pressed.emit()
	await _frames(3)
	check(main.screen == "game" and main.is_daily and main.index == main.daily_index(), "daily opens")
	var b: Board = main.board
	var p := b.puzzle
	check(main._grid.size.y > 400 and main._grid.cell_size() >= 80.0, "grid is big (cell %.0f)" % main._grid.cell_size())
	check(main._keys.size() == 27 and not main._keys.has("Ñ"), "EN keyboard: 26 letters + backspace")
	for k in main._keys.values():
		check(k.size.y >= 88.0 and k.get_global_rect().end.x <= main.size.x + 0.5, "key tall enough and on screen")
	check(main._keyboard.get_global_rect().end.y <= main.size.y + 0.5, "keyboard fits on screen")
	check(main._clue_text.text == b.current_clue().clue and main._clue_text.text != "", "clue bar shows active clue")
	# tap a cell, tap again to toggle
	var cell: int = p.white_cells()[3]
	_click_cell(cell)
	check(b.cursor == cell, "grid click selects the cell")
	var d0 := b.dir
	_click_cell(cell)
	check(b.dir != d0 or p.entry_at(cell, 1 - d0) < 0, "second click toggles direction")
	var dir_text: String = main._clue_dir.text
	check(dir_text.ends_with(tr("ACROSS")) or dir_text.ends_with(tr("DOWN")), "clue label shows direction")
	# arrows
	var e0 := b.current_entry()
	_find_icon(IconButton.Kind.NEXT).pressed.emit()
	check(b.current_entry() == (e0 + 1) % p.entries.size(), "next arrow")
	_find_icon(IconButton.Kind.PREV).pressed.emit()
	check(b.current_entry() == e0, "prev arrow")
	# fill everything wrong except last letter -> toast; then backspace + fix
	b.go_entry(0)
	for e in p.entries:
		if e.dir == Puzzle.ACROSS:
			b.go_entry(p.entries.find(e))
			_type(e.answer)
	await _frames(2)
	check(b.solved, "typing every across answer on the keyboard solves the puzzle")
	var t0 := Time.get_ticks_msec()
	while main._overlay == null and Time.get_ticks_msec() - t0 < 4000:
		await process_frame
	check(main._overlay != null and _find(main._overlay, tr("NEXT")) != null, "completion card with Next")
	check(_has_label(main._overlay, tr("SOLVED")), "celebration says Solved")
	check(settings.is_solved(p.id) and settings.best_time(p.id) >= 0.0, "best time stored")
	check(not settings.progress.has(p.id), "no stale progress after solving")
	# list shows the checkmark
	_find(main._overlay, tr("ALL")).pressed.emit()
	await _frames(3)
	check(main.screen == "list", "list opens from completion card")
	var tiles: Array = main._list.find_children("*", "Button", true, false).filter(func(x): return x.has_meta("solved"))
	check(tiles.size() == main.pack.size(), "one tile per puzzle (%d)" % tiles.size())
	check(tiles[main.daily_index()].get_meta("solved"), "solved tile marked")
	for tile in tiles:
		check(tile.size.y >= 88.0 and tile.size.x >= 88.0, "tile hit target")
	# resume: open another puzzle, type, leave, come back
	var other: int = (main.daily_index() + 1) % main.pack.size()
	tiles[other].pressed.emit()
	await _frames(2)
	var ob: Board = main.board
	check(ob.puzzle.id == main.pack[other].id and ob.filled_count() == 0, "other puzzle opens empty")
	ob.go_entry(0)
	var ans: String = ob.current_clue().answer
	_type(ans.substr(0, 2) + "Q")
	check(ob.filled_count() == 3, "typed three letters")
	main._keys["⌫"].pressed.emit()
	check(ob.filled_count() == 2, "backspace key clears")
	# full grid but wrong -> toast, not solved
	var w := main.board as Board
	for i in w.puzzle.cell_count():
		if not w.puzzle.is_block(i) and w.letters[i] == "":
			w.cursor = i
			w.dir = Puzzle.ACROSS if w.puzzle.across_of[i] >= 0 else Puzzle.DOWN
			main.press_key("Q")
	check(w.is_full() and not w.solved and main._toast.text.contains(tr("NOT_QUITE")), "full-but-wrong shows toast")
	# assist sheet: check word + reveal word, counted
	w.go_entry(0)
	_find_icon(IconButton.Kind.HELP).pressed.emit()
	await _frames(2)
	check(main._overlay != null, "assist sheet opens")
	for bt in _buttons(main._overlay):
		check(bt.size.y >= 88.0, "assist button '%s' >= 88 px" % bt.text)
	_find(main._overlay, tr("CHECK_WORD")).pressed.emit()
	check(w.checks == 1 and main._overlay == null, "check word counted, sheet closes")
	var marked := 0
	for i in w.puzzle.entries[0].cells:
		if w.wrong[i]:
			marked += 1
	check(marked >= 1, "check word marks wrong letters")
	_find_icon(IconButton.Kind.HELP).pressed.emit()
	await _frames(1)
	_find(main._overlay, tr("REVEAL_WORD")).pressed.emit()
	check(w.reveals == 1, "reveal counted")
	for i in w.puzzle.entries[0].cells:
		check(w.letters[i] == w.puzzle.solution[i], "reveal word fills answer")
	var id: String = w.puzzle.id
	var before: Array = w.letters.duplicate()
	_find_icon(IconButton.Kind.BACK).pressed.emit()
	await _frames(2)
	check(main.screen == "list" and settings.progress.has(id), "leaving saves progress")
	main.show_menu()
	await _frames(2)
	check(_find(main._menu, tr("CONTINUE")) != null, "menu offers Continue")
	settings.load_settings()
	_find(main._menu, tr("CONTINUE")).pressed.emit()
	await _frames(2)
	check(main.board.puzzle.id == id and main.board.letters == before and main.board.reveals == 1, "resume restores letters + counters from disk")
	# solve with reveals -> assisted (no best time)
	main.board.cursor = main.board.puzzle.white_cells()[0]
	for e in main.board.puzzle.entries:
		main.board.go_entry(main.board.puzzle.entries.find(e))
		main.assist(true, true)
	check(main.board.solved, "reveal-all solves")
	check(settings.is_solved(id) and settings.best_time(id) < 0.0, "assisted solve: checkmark, no best time")
	# how-to + language
	main.show_menu()
	await _frames(2)
	_find(main._menu, tr("HOWTO")).pressed.emit()
	await _frames(2)
	check(main._overlay != null and _has_label(main._overlay, tr("HOWTO")), "how-to opens")
	main._close_overlay()
	_find(main._menu, tr("LANG")).pressed.emit()
	await _frames(3)
	check(settings.language == "es" and main.lang == "es" and main.pack[0].id.begins_with("es-"), "language toggles pack")
	check(_find(main._menu, "Crucigrama del día") != null, "menu translated")
	_find(main._menu, tr("DAILY")).pressed.emit()
	await _frames(3)
	check(main._keys.has("Ñ") and main._keys.size() == 28, "ES keyboard has Ñ")
	check(main._clue_dir.text.ends_with("HORIZONTAL") or main._clue_dir.text.ends_with("VERTICAL"), "ES direction label")
	for k in main._keys.values():
		check(k.get_global_rect().end.x <= main.size.x + 0.5, "ES key inside screen")
	main.show_menu()
	await _frames(1)
	settings.set_language("en")
	DirAccess.remove_absolute(path)
	print("ui_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _find_icon(kind: int) -> IconButton:
	for c in main._game.find_children("*", "Button", true, false):
		if c is IconButton and c.kind == kind:
			return c
	return null


func _has_label(n: Node, text: String) -> bool:
	for l in n.find_children("*", "Label", true, false):
		if l.text == text:
			return true
	return false
