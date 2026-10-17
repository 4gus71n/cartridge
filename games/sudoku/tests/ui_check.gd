extends SceneTree
## UI-level bot: boots the real main scene and plays through the same entry
## points the buttons use (cells, number pad, tools): menu (EN + ES), notes,
## undo, hint, check toggle, full-but-wrong board, resume from the menu,
## a full solve to the win screen, records, and the daily streak.
## godot --headless --path . --script tests/ui_check.gd

const TEST_PATH := "user://ui_check_test.cfg"

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _texts(n: Node, out: Array) -> Array:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return out
	if n is Label or n is Button:
		out.append(n.text)
	for c in n.get_children():
		_texts(c, out)
	return out


func _find(n: Node, node_name: String) -> Node:
	return n.find_child(node_name, true, false)


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var settings := root.get_node("Settings")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	settings.load_from(TEST_PATH)
	settings.set_language("en")
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(2)
	var texts := _texts(main, [])
	check(texts.has("SUDOKU") and texts.has("Daily puzzle"), "menu shows title + daily")
	check(texts.has("Easy") and texts.has("Medium") and texts.has("Hard"), "menu lists 3 levels")
	check(_find(main, "Continue") == null, "no Continue without a save")
	(_find(main, "Language") as Button).pressed.emit()
	await _frames(2)
	texts = _texts(main, [])
	check(texts.has("Puzle del día") and texts.has("Difícil") and texts.has("English"), "menu translated to ES")
	(_find(main, "Language") as Button).pressed.emit()
	await _frames(2)

	# --- play a Medium game through the pad ---
	(_find(main, "Level2") as Button).pressed.emit()
	await _frames(2)
	var g: SudokuGame = main.game
	check(g != null and g.level == 2 and main.board.visible, "game started from menu")
	check(main.board.cell_size() >= 70.0, "board cells are touch-sized (%.0f px)" % main.board.cell_size())
	var k1: Control = _find(main, "Digit1")
	check(k1.size.x >= 88.0 and k1.size.y >= 88.0, "number keys >= 88 px (%s)" % k1.size)
	check((_find(main, "Digit9") as Control).size.x >= 88.0, "second-row keys >= 88 px")
	var empties := []
	for i in 81:
		if g.values[i] == 0:
			empties.append(i)
	var a: int = empties[0]
	main.press_digit(5)
	check(g.values[a] == 0, "digit without a selection does nothing")
	main.press_cell(a)
	check(main.board.selected == a, "tap selects a cell")
	# Notes mode.
	main.press_tool("notes")
	check(main.notes_mode and (_find(main, "Digit3") as PadKey).notes_mode, "notes mode on")
	main.press_digit(3)
	main.press_digit(7)
	check(g.notes[a] == (1 << 3) | (1 << 7), "pencil marks via pad")
	main.press_tool("notes")
	var sol: int = g.solution[a]
	var wrong: int = sol % 9 + 1
	main.press_digit(wrong)
	check(g.values[a] == wrong and g.mistakes == 1, "wrong digit entered + counted")
	check((_find(main, "Digit%d" % wrong) as PadKey).remaining == g.remaining(wrong), "pad remaining count updates")
	main.press_tool("undo")
	check(g.values[a] == 0 and g.notes[a] == (1 << 3) | (1 << 7), "undo restores the notes")
	main.press_digit(sol)
	check(g.values[a] == sol, "correct digit entered")
	main.press_digit(sol)
	check(g.values[a] == 0, "same digit again clears it")
	main.press_digit(sol)
	main.press_cell(empties[1])
	main.press_tool("hint")
	check(g.hints_used == 1 and g.values[empties[1]] == g.solution[empties[1]], "hint reveals the selected cell")
	check((_find(main, "Tool_hint") as PadKey).badge == "1", "hint badge counts")
	main.press_tool("check")
	check(not settings.mistake_check and not main.board.mistake_check, "mistake check off")
	main.press_tool("check")
	check(settings.mistake_check, "mistake check back on")

	# --- leave, resume from the menu ---
	var vals := g.values.duplicate()
	(_find(main, "Back") as Button).pressed.emit()
	await _frames(2)
	var cont := _find(main, "Continue") as Button
	check(cont != null and cont.is_visible_in_tree(), "menu offers Continue")
	cont.pressed.emit()
	await _frames(2)
	check(main.game != null and main.game.values == vals and main.game.hints_used == 1, "resumed game state")
	g = main.game

	# --- full-but-wrong, then solve ---
	var open := []
	for i in 81:
		if g.values[i] != g.solution[i]:
			open.append(i)
	for k in open.size():
		var i: int = open[k]
		main.press_cell(i)
		main.press_digit(g.solution[i] if k < open.size() - 1 else g.solution[i] % 9 + 1)
	check(g.is_full() and not g.won and not main.is_win_shown(), "full board with an error is not a win")
	check(main._toast.text == "Board full, but some digits are wrong", "full-but-wrong toast")
	var last: int = open[-1]
	main.press_cell(last)
	main.press_tool("erase")
	check(g.values[last] == 0, "erase tool clears the cell")
	main.press_digit(g.solution[last])
	check(g.won, "game won")
	var t := 0.0
	while not main.is_win_shown() and t < 3.0:
		await process_frame
		t += 1.0 / 60.0
	await _frames(2)
	texts = _texts(main, [])
	check(main.is_win_shown() and texts.has("Solved!"), "win screen shown")
	check(texts.has("New best time!"), "first solve is a new best")
	check(texts.has("Next puzzle") and texts.has("Menu"), "win screen buttons")
	check(settings.best_times[2] > 0.0 and settings.saved_game.is_empty(), "record saved, save cleared")
	(_find(main, "Next") as Button).pressed.emit()
	await _frames(2)
	check(main.game != null and main.game != g and main.game.level == 2 and not main.is_win_shown(), "next puzzle starts")
	(_find(main, "Back") as Button).pressed.emit()
	await _frames(2)
	texts = _texts(main, [])
	check(texts.has("Best %s" % main.fmt_time(settings.best_times[2])), "menu shows best time")

	# --- daily: solve it with hints, streak recorded, button disabled ---
	settings.clear_game()
	var today := SudokuGame.today()
	main.start_daily(today)
	await _frames(1)
	check(main.game.daily_day == today and main._title_label.text == "Medium · Daily", "daily started")
	var guard := 0
	while not main.game.won and guard < 81:
		main.press_tool("hint")
		guard += 1
	check(main.game.won, "daily solved via hints")
	check(settings.streak == 1 and settings.daily_done(today), "daily streak recorded")
	t = 0.0
	while not main.is_win_shown() and t < 3.0:
		await process_frame
		t += 1.0 / 60.0
	await _frames(2)
	texts = _texts(main, [])
	check(texts.has("Daily streak 1"), "win screen shows streak")
	(_find(main, "Menu") as Button).pressed.emit()
	await _frames(2)
	var daily := _find(main, "Daily") as Button
	check(daily.disabled and _texts(main, []).has("Daily solved - come back tomorrow"), "daily locked for today")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	print("ui_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
