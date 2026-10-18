extends SceneTree
## UI bot: boots the real main scene and plays full games through the same
## entry points the buttons use: menu, first clip only from a tap, choices
## locked until listening, right/wrong reveal with fact + source, streak
## label, pause + save & exit + resume, summary + best score per mode,
## Hard mode with 6 choices, credits screen, language toggle, hit targets.

var _pass := 0
var _fail := 0
var main: Control
var bank: ClipBank


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
	var path := dir.path_join("babel-work/ui_test.cfg")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	DirAccess.remove_absolute(path)
	var settings = root.get_node("Settings")
	settings.load_from(path)
	settings.set_language("en")
	root.size = Vector2i(720, 1280)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred(settings, path)


func _frames(n := 3) -> void:
	for i in n:
		await process_frame


func _wait(t: float) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < t * 1000.0:
		await process_frame


func _run(settings, path: String) -> void:
	await _frames()
	bank = main.bank
	check(main.phase == main.Phase.MENU, "boots into the menu")
	check(main._menu.find_child("Easy", true, false) != null and main._menu.find_child("Hard", true, false) != null, "menu has Easy + Hard")
	check(main._menu.find_child("Resume", true, false) == null, "no resume on a fresh profile")
	_targets(main._menu, "menu")
	await _full_game(settings, BabelGame.EASY, true)
	await _pause_resume(settings)
	await _full_game(settings, BabelGame.HARD, false)
	await _credits()
	await _toggle_language(settings)
	DirAccess.remove_absolute(path)
	main.queue_free()
	await _frames(2)
	print("ui_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _targets(node: Node, where: String) -> void:
	for b in node.find_children("*", "Button", true, false):
		if b.is_visible_in_tree():
			check(b.size.y >= 88 and b.size.x >= 88, "%s: hit target %s >= 88 px (%s)" % [where, b.name, b.size])


func _button_with(node: Node, text: String) -> Button:
	for b in node.find_children("*", "Button", true, false):
		if b.text == text:
			return b
	return null


func _full_game(settings, mode: int, perfect: bool) -> void:
	main.start_game(mode, 1234 + mode)
	await _frames(4)
	check(main.phase == main.Phase.LISTEN, "game starts listening")
	check(main._round_label.text == "Round 1 / 10", "round label (%s)" % main._round_label.text)
	var n := 4 if mode == BabelGame.EASY else 6
	check(main._choice_buttons.size() == n, "%d choice buttons" % n)
	_targets(main._game, "round")
	if mode == BabelGame.EASY:
		check(not main.playing and not main.heard_current, "first clip does not autoplay (needs a tap)")
		check(main._play_btn.pulse, "play button pulses to invite the tap")
		var any_btn: Button = main._choice_buttons.values()[0]
		check(any_btn.disabled, "choices locked before listening")
		main.choose(main._choice_buttons.keys()[0])
		check(main.phase == main.Phase.LISTEN and main.game.round_index() == 0, "choose ignored before listening")
		main._play_btn.pressed.emit()  # the user's tap
		await _frames(2)
		check(main.playing and main.audio_unlocked, "tap starts the clip")
		check(not any_btn.disabled, "choices unlocked after listening starts")
		check(main._player.stream is AudioStreamOggVorbis, "player has the clip stream")
		await _wait(0.4)
		check(main._wave.progress > 0.0, "waveform progress advances (%.2f)" % main._wave.progress)
		main._play_btn.pressed.emit()  # stop
		check(not main.playing and main._play_btn.kind == "replay", "tap again stops; replay icon")
		main._play_btn.pressed.emit()  # replay
		check(main.playing, "replay restarts the clip")
	for i in BabelGame.ROUNDS:
		await _frames(2)
		if i > 0:
			check(main.playing, "round %d autoplays after the Next tap" % (i + 1))
		var truth: String = main.game.truth_of(i, bank)
		check(main._choice_buttons.has(truth), "truth among choice buttons")
		var pick := truth
		if not perfect and i % 3 == 1:
			for c in main._choice_buttons:
				if c != truth:
					pick = c
					break
		var btn: Button = main._choice_buttons[pick]
		check(btn.text == bank.name_of(pick), "button shows language name")
		btn.pressed.emit()
		await _frames(2)
		check(main.phase == main.Phase.REVEAL, "reveal after answering")
		check(main.last_result["correct"] == (pick == truth), "result correctness")
		var reveal: Node = main._bottom.find_child("Reveal", true, false)
		check(reveal != null, "reveal card shown")
		if reveal:
			var name_l: Label = reveal.find_child("LangName", true, false)
			check(name_l.text == bank.name_of(truth), "reveal names the language")
			var src: Label = reveal.find_child("Source", true, false)
			var clip: Dictionary = bank.by_id[main.game.clip_ids[i]]
			check(str(clip["reader_display"]) in src.text and "LibriVox" in src.text, "reveal shows source + reader")
			var texts := ""
			for l in reveal.find_children("*", "Label", true, false):
				texts += l.text + "\n"
			check(bank.fact_of(truth) in texts and bank.where_of(truth) in texts, "reveal shows fact + where spoken")
		main.choose(truth)  # double tap ignored
		check(main.game.round_index() == i + 1, "second answer ignored")
		if perfect and i >= 1:
			check("×" in main._streak_label.text, "streak label shows multiplier")
		var next: Button = main._bottom.find_child("Next", true, false)
		check(next != null, "next button")
		if i == 0:
			_targets(main._game, "reveal")
		if i == BabelGame.ROUNDS - 1:
			check(next.text == tr("SEE_RESULTS"), "last reveal offers results")
		next.pressed.emit()
		await _frames(2)
	check(main.phase == main.Phase.SUMMARY, "summary after 10 rounds")
	var key: String = BabelGame.MODE_KEYS[mode]
	if perfect:
		check(main.game.score == 4000, "perfect easy = 4000 (%d)" % main.game.score)
	check(settings.best_for(key) == main.game.score, "best score saved for " + key)
	check(main.record, "first game of a mode is a record")
	check((main._summary.find_child("FinalScore", true, false) as Label).text == main._fmt(main.game.score), "summary score label")
	check(main._summary.find_child("Rounds", true, false).get_child_count() == 10, "summary lists 10 rounds")
	check(settings.saved_game.is_empty(), "finished game is not resumable")
	_targets(main._summary, "summary")
	(main._summary.find_child("Menu", true, false) as Button).pressed.emit()
	await _frames(2)
	check(main.phase == main.Phase.MENU, "back to menu")


func _pause_resume(settings) -> void:
	main.start_game(BabelGame.EASY, 99)
	await _frames(2)
	main.play_clip()
	var first: String = main.game.truth_of(0, bank)
	main.choose(first)
	(main._bottom.find_child("Next", true, false) as Button).pressed.emit()
	await _frames(2)
	var ids: Array = main.game.clip_ids.duplicate()
	var score: int = main.game.score
	(main._game.find_child("Pause", true, false) as Button).pressed.emit()
	await _frames(2)
	check(main.has_overlay() and not main.playing, "pause shows overlay and stops audio")
	_targets(main._overlay, "pause")
	(main._overlay.find_child("Continue", true, false) as Button).pressed.emit()
	await _frames(2)
	check(not main.has_overlay() and main.phase == main.Phase.LISTEN, "continue closes overlay")
	main.pause()
	(main._overlay.find_child("SaveExit", true, false) as Button).pressed.emit()
	await _frames(2)
	check(main.phase == main.Phase.MENU, "save & exit to menu")
	var res: Button = main._menu.find_child("Resume", true, false)
	check(res != null and "2/10" in res.text, "menu offers resume at round 2")
	res.pressed.emit()
	await _frames(2)
	check(main.phase == main.Phase.LISTEN and main.game.round_index() == 1, "resumed at round 2")
	check(main.game.clip_ids == ids and main.game.score == score, "resumed same clips + score")
	main.pause()
	(main._overlay.find_child("Abandon", true, false) as Button).pressed.emit()
	await _frames(2)
	check(main.phase == main.Phase.MENU and main._menu.find_child("Resume", true, false) == null, "abandon clears resume")
	check(settings.best_for("easy") == 4000, "abandoning keeps the best")


func _credits() -> void:
	(main._menu.find_child("Credits", true, false) as Button).pressed.emit()
	await _frames(3)
	check(main.phase == main.Phase.CREDITS, "credits screen")
	var list: Node = main._credits.find_child("List", true, false)
	var all := ""
	for l in list.find_children("*", "Label", true, false):
		all += l.text + "\n"
	check("LibriVox" in all and "public domain" in all, "credits mention LibriVox public domain")
	var missing := 0
	for c in bank.clips:
		if not (str(c["reader_display"]) in all):
			missing += 1
	check(missing == 0, "credits list every reader (%d missing)" % missing)
	var scroll: ScrollContainer = main._credits.find_child("Scroll", true, false)
	var drag := InputEventScreenDrag.new()
	drag.relative = Vector2(0, -300)
	scroll.gui_input.emit(drag)
	await _frames(2)
	check(scroll.scroll_vertical > 0, "credits scroll by dragging")
	(main._credits.find_child("Back", true, false) as Button).pressed.emit()
	await _frames(2)
	check(main.phase == main.Phase.MENU, "credits back to menu")


func _toggle_language(settings) -> void:
	(main._menu.find_child("Language", true, false) as Button).pressed.emit()
	await _frames(2)
	check(settings.language == "es", "language toggled to es")
	check(_button_with(main._menu, "English") != null, "menu rebuilt in Spanish")
	main.start_game(BabelGame.HARD, 5)
	await _frames(2)
	var code: String = main.game.current_choices()[0]
	check((main._choice_buttons[code] as Button).text == bank.langs[code]["name_es"], "choices in Spanish")
	main.abandon_game()
	await _frames(2)
	(main._menu.find_child("Language", true, false) as Button).pressed.emit()
	await _frames(2)
	check(settings.language == "en", "language back to en")
