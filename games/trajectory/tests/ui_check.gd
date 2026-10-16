extends SceneTree
## UI bot: boots the real main scene and plays through it with the same
## entry points the buttons use (nudge / press_key / launch), fast-forwarding
## flights. Covers lose paths (miss, crash, parse error), win path + result
## sheet, persistence of stars and drafts, and solves EVERY level via the UI.

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
	var dir := OS.get_environment("TMPDIR")
	if dir == "":
		dir = OS.get_user_data_dir()
	path = dir.path_join("trajectory-work/ui_test.cfg")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	DirAccess.remove_absolute(path)
	var settings = root.get_node("Settings")
	settings.path = path
	settings.progress = Progress.new()
	settings.language = "en"
	TranslationServer.set_locale("en")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred(settings)


func _run(settings) -> void:
	await process_frame
	check(main.is_node_ready(), "main scene ready")
	check(main._screen != null, "menu built")
	_lose_and_win(settings)
	_errors_and_keypad(settings)
	_drafts(settings)
	_every_level(settings)
	_levels_screen()
	DirAccess.remove_absolute(path)
	print("ui_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func fly() -> void:
	main.launch()
	main._plot.finish_now()


func _lose_and_win(settings) -> void:
	main._open_level(0)
	check(main.has_overlay(), "level 1 shows its teaching blurb")
	check(settings.progress.seen.has("CONST"), "blurb marked seen")
	main._close_overlay()
	main.launch()
	check(main._plot.is_flying(), "launch starts a flight")
	check(main.tries == 1, "launch counts an attempt")
	main.launch()
	check(main.tries == 1, "no double launch while flying")
	main._plot.finish_now()
	check(not main.won and main._status.text == tr("MISSED_N") % 2, "y = 0 misses both rings (%s)" % main._status.text)
	check(main._plot.ghost.size() > 100, "failed path kept as a ghost")
	check(settings.progress.draft(0).get("tries", 0) == 1, "attempt saved in the draft")
	for k in 3:
		main.nudge("c", 1)
	check(main.values.c == 3.0, "steppers moved c to 3")
	check(main._eq.text.contains("3"), "equation shows the value")
	fly()
	check(main.won, "y = 3 wins level 1")
	check(settings.progress.best(0) == 2, "2 launches = 2 stars")
	check(main.has_overlay(), "result sheet shown")
	check(main._plot.ideal != null, "ideal curve drawn after solving")
	check(_overlay_has("y = 3"), "result sheet shows the ideal answer")
	check(not _overlay_has(tr("ALL_DONE")), "no 'all done' after level 1")
	main.nudge("c", 1)
	check(main.values.c == 3.0, "inputs frozen after winning")
	var p := Progress.new()
	check(p.load_from(path) and p.best(0) == 2 and p.draft(0).is_empty(), "stars persisted, draft cleared")
	# Replay with a first-try win keeps the better record.
	main._open_level(0)
	for k in 3:
		main.nudge("c", 1)
	fly()
	check(settings.progress.best(0) == 3, "first-launch replay = 3 stars")
	# Crash path: level 2 starts at y = 0, straight into an asteroid.
	main._open_level(1)
	fly()
	check(main._status.text == tr("CRASH_ROCK"), "asteroid crash message (%s)" % main._status.text)
	check(not main.won, "crash does not win")
	# Wall crash: level 3 at y = 0 hits the lower wall.
	main._open_level(2)
	fly()
	check(main._status.text == tr("CRASH_WALL"), "wall crash message (%s)" % main._status.text)


func _errors_and_keypad(settings) -> void:
	var i := Levels.world_start(4)
	main._open_level(i)
	check(main.has_overlay(), "keypad world opens with its blurb")
	main._close_overlay()
	main.launch()
	check(main._status.text == tr("ERR_EMPTY") and main.tries == 0, "empty formula: error, no attempt")
	main.press_key("+")
	main.launch()
	check(main._status.text == tr("ERR_INCOMPLETE") and main.tries == 0, "incomplete formula: error, no attempt")
	main.press_key("back")
	for k in ["1", "/", "x"]:
		main.press_key(k)
	fly()
	check(main._status.text == tr("CRASH_UNDEF") % "0", "1/x breaks at x = 0 (%s)" % main._status.text)
	main.press_key("clear")
	for k in ["2", "x", "+", "1"]:
		main.press_key(k)
	check(main._eq.text.contains("2x+1"), "keypad shows the formula")
	check(main._plot.preview != null, "live preview on easy keypad level")
	fly()
	check(main.won and settings.progress.best(i) == 2, "2x+1 solves the first keypad level in 2 launches")


func _drafts(settings) -> void:
	var i := Levels.world_start(1) + 3  # y = mx + b with m locked
	main._open_level(i)
	main._close_overlay()
	main.nudge("b", 1)
	main.nudge("m", 1)  # locked: ignored
	main.launch()
	main._plot.finish_now()
	main._show_levels()
	var d: Dictionary = settings.progress.draft(i)
	check(d.get("tries", 0) == 1, "draft keeps the attempt count")
	main._open_level(i)
	check(main.values.b == 1.0 and main.values.m == 1.0 and main.tries == 1, "draft restored on reopen")
	var p := Progress.new()
	p.load_from(path)
	check(p.draft(i).get("tries", 0) == 1, "draft persisted to disk")


func _keys_for(src: String) -> Array:
	var kb := KeyBuffer.new()
	kb.set_text(src)
	var keys := []
	for t in kb.tokens:
		keys.append(t if t == "(" else t.trim_suffix("("))
	return keys


func _every_level(settings) -> void:
	for i in Levels.count():
		var lvl: Dictionary = Levels.get_level(i)
		main._open_level(i)
		main._close_overlay()
		if lvl.form == "free":
			main.press_key("clear")
			for k in _keys_for(lvl.ideal):
				main.press_key(k)
		else:
			for p in main.params:
				var want := float(lvl.ideal[p.name])
				var guard := 200
				while not is_equal_approx(main.values[p.name], want) and guard > 0:
					main.nudge(p.name, 1 if want > main.values[p.name] else -1)
					guard -= 1
		var e: MathExpr = main.current_expr()
		check(e.ok, "level %d: ideal input parses" % (i + 1))
		fly()
		check(main.won, "level %d solved through the UI" % (i + 1))
		check(settings.progress.solved(i), "level %d recorded" % (i + 1))
		check(i == Levels.count() - 1 or settings.progress.unlocked(i + 1), "level %d unlocks the next" % (i + 1))
	check(settings.progress.next_level(Levels.count()) == Levels.count() - 1, "everything solved")
	check(_overlay_has(tr("ALL_DONE")), "final result sheet congratulates on finishing every level")


func _overlay_has(text: String) -> bool:
	if not main.has_overlay():
		return false
	for n in main._overlay.find_children("*", "Label", true, false):
		if (n as Label).text == text:
			return true
	return false


func _levels_screen() -> void:
	main._show_levels()
	check(main._screen != null and not main.has_overlay(), "level select builds")
	main._show_menu()
	check(main._screen != null, "menu rebuilds after progress")
