extends SceneTree
## UI-level bot: boots the real main scene, plays a whole game through the
## same action API the touch gestures use, and checks pause + game-over UI.
## godot --headless --path . --script tests/main_check.gd

const TEST_PATH := "user://main_check_test.cfg"

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _labels(n: Node, out: Array) -> Array:
	if n is Label or n is Button:
		out.append(n.text)
	for c in n.get_children():
		_labels(c, out)
	return out


func _initialize() -> void:
	_run()


func _run() -> void:
	var settings := root.get_node("Settings")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	settings.load_from(TEST_PATH)
	settings.set_language("en")
	Engine.time_scale = 4.0
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var texts := _labels(main, [])
	check(texts.has("PENTAPRISM"), "menu shows title")
	check(texts.has("Play"), "menu has Play")

	settings.set_language("es")
	main._show_menu()
	await process_frame
	await process_frame
	texts = _labels(main, [])
	check(texts.has("PENTAPRISMA") and texts.has("Jugar"), "menu translated to ES")
	settings.set_language("en")

	main.start_game(21)
	await process_frame
	check(main.board != null and main.board.state == PrismBoard.State.PLAYING, "game started")
	check(main.view.cell_size() >= 40.0, "board cells are touch-sized (%.0f px)" % main.view.cell_size())

	# Gesture-level actions.
	var x0: int = main.board.current.pos.x
	main._do("left")
	check(main.board.current.pos.x == x0 - 1, "left action moves piece")
	main._do("right")
	main._do("rotate")
	main._do("hold")
	check(main.board.held != null, "hold action stores piece")

	# Pause stops gravity.
	main._pause()
	var y0: int = main.board.current.pos.y
	for i in 30:
		await process_frame
	check(main.paused and main.board.current.pos.y == y0, "paused: piece doesn't fall")
	main._resume()
	check(not main.paused, "resumed")

	# Play to the end with hard drops (alternating columns to vary the stack).
	var frames := 0
	var drops := 0
	while main.board.state != PrismBoard.State.OVER and frames < 20000:
		if main.board.state == PrismBoard.State.PLAYING:
			for k in (drops % 5) - 2:
				main._do("right")
			main._do("hard")
			drops += 1
		await process_frame
		frames += 1
	check(main.board.state == PrismBoard.State.OVER, "bot game reached game over (%d drops)" % drops)
	var waited := 0
	while main._overlay == null and waited < 600:
		await process_frame
		waited += 1
	await process_frame
	check(main._overlay != null, "game-over overlay shown")
	texts = _labels(main._overlay, [])
	check(texts.has("Game over"), "overlay says Game over")
	check(texts.has(str(main.board.score)), "overlay shows final score")
	check(texts.has("Play again"), "overlay offers Play again")
	check(settings.best_score == main.board.score and main.board.score > 0, "best score saved (%d)" % settings.best_score)

	main.start_game(22)
	await process_frame
	check(main._overlay == null and main.board.state == PrismBoard.State.PLAYING, "play again restarts")
	main._show_menu()
	await process_frame
	texts = _labels(main, [])
	check(texts.any(func(t: String) -> bool: return t.begins_with("Best %d" % settings.best_score)), "menu shows best")

	Engine.time_scale = 1.0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	print("main_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
