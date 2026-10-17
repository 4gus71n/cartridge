extends SceneTree
## UI bot: boots the real main scene and plays it through the same entry
## points the buttons use. Covers the correct / wrong / timeout paths, the
## feedback card, pause, game over + best-score save, review, Learn browsing,
## language toggle, hit-target sizes, and draws every sign once.

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
	path = dir.path_join("row-work/ui_test.cfg")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	DirAccess.remove_absolute(path)
	var settings = root.get_node("Settings")
	settings.path = path
	settings.best_score = 0
	settings.best_streak = 0
	settings.runs = 0
	settings.language = "en"
	TranslationServer.set_locale("en")
	root.size = Vector2i(720, 1280)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred(settings)


func _frames(n := 2) -> void:
	for i in n:
		await process_frame


func _run(settings) -> void:
	await _frames()
	check(main._menu != null, "menu built")
	check(_find_text(main._menu, tr("MODE_ENDLESS")) != null, "menu has the Endless button")
	await _menu_targets()
	await _play_run(settings)
	await _second_run(settings)
	await _learn()
	await _language(settings)
	await _draw_all()
	DirAccess.remove_absolute(path)
	print("ui_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _menu_targets() -> void:
	await _frames()
	for b in _buttons(main._menu):
		check(b.size.y >= 88.0, "menu button '%s' >= 88 px tall (%.0f)" % [b.text, b.size.y])


## Clock ticks forward in small steps like real frames.
func tick(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		main._process(0.05)
		t += 0.05


func _play_run(settings) -> void:
	main.start_run(3)
	await _frames()
	check(main.phase == main.Phase.ASK, "run starts asking")
	check(main._choice_buttons.size() == 3, "warm-up shows 3 choices")
	for i in main._choice_buttons.size():
		var b: Button = main._choice_buttons[i]
		check(b.text == tr(SignCatalog.action_key(main.question.choices[i])), "button %d shows its action" % i)
		check(b.size.y >= 88.0, "choice button >= 88 px (%.0f)" % b.size.y)
	check(is_equal_approx(main.time_limit, 4.5), "first question has 4.5 s")
	# Intro: the clock waits for the sign to pop in.
	tick(0.2)
	check(is_equal_approx(main.time_left, 4.5), "clock paused during the intro")
	tick(1.0)
	check(main.time_left < 4.5 and main.time_left > 3.0, "clock runs (%.2f)" % main.time_left)
	check(main._timer.ratio < 1.0, "timer bar shrinks")

	# Correct answer (via a real button press).
	var first_id: String = main.question.id
	main._choice_buttons[main.question.answer].pressed.emit()
	check(main.last_correct and main.run.score > 100 and main.run.streak == 1, "correct answer scores (%d)" % main.run.score)
	check(main.phase == main.Phase.REVEAL, "reveal after answering")
	main.answer(0)
	check(main.run.answered == 1, "no double answer during reveal")
	tick(0.7)
	check(main.phase == main.Phase.ASK and main.question.id != first_id, "next sign after a correct answer")
	check(main.time_limit < 4.5, "timer shorter with a streak (%.3f)" % main.time_limit)

	# Five more correct -> x2 and 4 choices.
	for k in 5:
		tick(0.4)
		main.answer(main.question.answer)
		tick(0.7)
	check(main.run.streak == 6 and main.run.multiplier() == 2, "streak 6 = x2")
	check(main._choice_buttons.size() == 4, "4 choices after warm-up")
	check(main._streak_label.text.contains("×2"), "HUD shows the multiplier (%s)" % main._streak_label.text)

	# Wrong answer -> feedback card with the sign's meaning.
	tick(0.4)
	var wrong_id: String = main.question.id
	var wrong: int = (main.question.answer + 1) % main.question.choices.size()
	main._choice_buttons[wrong].pressed.emit()
	check(not main.last_correct and main.run.lives == 2 and main.run.streak == 0, "wrong answer costs a life + streak")
	check(main._lives.lives == 2, "hearts updated")
	tick(1.0)
	check(main.phase == main.Phase.FEEDBACK and main._feedback.visible, "feedback card shown")
	check(_find_text(main._feedback, tr(SignCatalog.name_key(wrong_id))) != null, "feedback names the sign")
	check(_find_text(main._feedback, tr(SignCatalog.action_key(wrong_id))) != null, "feedback shows the right action")
	check(_find_text(main._feedback, tr(SignCatalog.explain_key(wrong_id))) != null, "feedback explains it")
	tick(5.0)
	check(main.phase == main.Phase.FEEDBACK, "feedback waits for the player")

	# Pause freezes everything.
	main._next_button.pressed.emit()
	check(main.phase == main.Phase.ASK, "Next goes on")
	main.pause()
	check(main.paused and main.has_overlay(), "pause overlay")
	var tl: float = main.time_left
	tick(3.0)
	check(main.time_left == tl, "clock frozen while paused")
	main.answer(main.question.answer)
	check(main.phase == main.Phase.ASK, "no answering while paused")
	main.resume()
	check(not main.paused and not main.has_overlay(), "resume")

	# Timeout -> life lost.
	tick(6.0)
	check(main.last_timeout and main.run.lives == 1, "timeout costs a life")
	check(main.phase == main.Phase.FEEDBACK, "timeout shows feedback")
	check(_find_text(main._feedback, tr("TIMEOUT")) != null, "timeout says too slow")
	main.advance()
	# Last life.
	tick(6.0)
	check(main.run.is_over(), "third miss ends the run")
	check(main._next_button.text == tr("SEE_RESULTS"), "button says See results")
	var score: int = main.run.score
	main.advance()
	await _frames()
	check(main.phase == main.Phase.OVER and main.has_overlay(), "game over overlay")
	check(settings.best_score == score and score > 0, "best score recorded (%d)" % score)
	check(main.record, "first run is a record")
	check(_find_text(main._overlay, tr("NEW_BEST")) != null, "NEW BEST shown")
	check(_find_text(main._overlay, str(score)) != null, "final score shown")
	var cfg := ConfigFile.new()
	check(cfg.load(path) == OK and int(cfg.get_value("records", "best_score", 0)) == score, "best score saved to disk")
	check(main.run.missed.size() == 3, "3 missed signs listed (%d)" % main.run.missed.size())

	# Review missed -> Learn with the detail card open.
	var review := _find_text(main._overlay, tr("REVIEW")) as Button
	check(review != null, "review button")
	review.pressed.emit()
	await _frames()
	check(main._learn != null and main.has_overlay(), "review opens the guide + card")
	check(main.detail_ids.size() == 3 and main.detail_ids[0] == wrong_id, "review starts with the first missed sign")
	main._close_overlay()
	main.show_menu()
	await _frames()
	check(_find_text(main._menu, tr("BEST") % score) != null, "menu shows the best score")


func _second_run(settings) -> void:
	var best: int = settings.best_score
	main.start_run(9)
	for k in 3:
		tick(6.0)
		main.advance()
	await _frames()
	check(main.phase == main.Phase.OVER, "all-timeout run ends")
	check(main.run.score == 0 and not main.record, "zero run is not a record")
	check(settings.best_score == best, "best score unchanged")
	check(settings.runs == 2, "runs counted")
	check(_find_text(main._overlay, tr("BEST") % best) != null, "over screen shows the standing best")
	# Quit from pause also ends the run cleanly.
	main.start_run(10)
	tick(0.5)
	main.answer(main.question.answer)
	main.pause()
	var quit_btn := _find_text(main._overlay, tr("QUIT_RUN")) as Button
	quit_btn.pressed.emit()
	await _frames()
	check(main.phase == main.Phase.OVER and settings.runs == 3, "End run from pause shows results")
	var menu_btn := _find_text(main._overlay, tr("MENU")) as Button
	menu_btn.pressed.emit()
	await _frames()
	check(main._menu != null and main.run == null or main._game == null, "back to the menu")


func _learn() -> void:
	main.show_learn()
	await _frames(3)
	var tiles := _all_of(main._learn, "SignTile")
	check(tiles.size() == SignCatalog.count(), "guide shows every sign (%d)" % tiles.size())
	for t in tiles:
		if t.size.y < 88.0 or t.size.x < 88.0:
			check(false, "tile %s too small %s" % [t.sign_id, t.size])
			break
	tiles[0].tapped.emit(tiles[0].sign_id)
	await _frames()
	check(main.has_overlay() and main.detail_index == 0, "tap a tile opens its card")
	var id0: String = main.detail_ids[0]
	check(_find_text(main._overlay, tr(SignCatalog.explain_key(id0))) != null, "card explains the sign")
	(_find_name(main._overlay, "NextSign") as Button).pressed.emit()
	await _frames()
	check(main.detail_index == 1, "next card")
	(_find_name(main._overlay, "Prev") as Button).pressed.emit()
	(_find_name(main._overlay, "Prev") as Button).pressed.emit()
	await _frames()
	check(main.detail_index == main.detail_ids.size() - 1, "prev wraps around")
	# Swipe left = next.
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(500, 600)
	main._detail_swipe(down)
	var up := down.duplicate()
	up.pressed = false
	up.position = Vector2(300, 610)
	main._detail_swipe(up)
	await _frames()
	check(main.detail_index == 0, "swipe left goes to the next card")
	(_find_name(main._overlay, "Close") as Button).pressed.emit()
	await _frames()
	check(not main.has_overlay(), "close card")
	(_find_name(main._learn, "Back") as Button).pressed.emit()
	await _frames()
	check(main._menu != null and main._learn == null, "back to menu")


func _language(settings) -> void:
	var lang := _find_text(main._menu, tr("LANGUAGE")) as Button
	lang.pressed.emit()
	await _frames()
	check(settings.language == "es", "language toggled to es")
	check(_find_text(main._menu, "Partida sin fin") != null, "menu in Spanish")
	main.start_run(4)
	await _frames()
	check(main._choice_buttons[0].text == TranslationServer.translate(SignCatalog.action_key(main.question.choices[0])), "choices in Spanish")
	main.show_menu()
	await _frames()
	(_find_text(main._menu, "English") as Button).pressed.emit()
	await _frames()
	check(settings.language == "en", "back to English")


## Every pictogram goes through _draw once (catches runtime errors in painters).
func _draw_all() -> void:
	var holder := Control.new()
	holder.size = Vector2(720, 1280)
	root.add_child(holder)
	for i in SignCatalog.count():
		var v := SignView.new()
		v.size = Vector2(90, 90)
		v.position = Vector2((i % 8) * 90, (i / 8) * 90)
		holder.add_child(v)
		v.sign_id = SignCatalog.ids()[i]
	await _frames(3)
	check(holder.get_child_count() == SignCatalog.count(), "drew every sign")
	holder.queue_free()


func _buttons(n: Node) -> Array:
	var out := []
	for c in n.find_children("*", "Button", true, false):
		if c.is_visible_in_tree():
			out.append(c)
	return out


func _all_of(n: Node, cls: String) -> Array:
	var out := []
	for c in n.find_children("*", "", true, false):
		if c.get_script() != null and c.get_script().get_global_name() == cls:
			out.append(c)
	return out


func _find_text(n: Node, text: String) -> Control:
	if n == null:
		return null
	for c in n.find_children("*", "", true, false):
		if (c is Label or c is Button) and c.text == text:
			return c
	return null


func _find_name(n: Node, nm: String) -> Node:
	return n.find_child(nm, true, false)
