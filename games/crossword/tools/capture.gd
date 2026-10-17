extends SceneTree
## Hermetic screenshots (needs a display, not --headless):
##   godot --path . --script tools/capture.gd -- <out_dir> [lang] [height] [only]
## Saves menu / game / assist / done / list / howto PNGs at 720 x <height>.
## `only` = "poster" writes just <out_dir>/poster.png: a partly filled grid
## with the active clue and the keyboard.

var main: Control
var out_dir := ""


func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	for k in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var p := out_dir.path_join(name + ".png")
	img.save_png(p)
	print("capture: ", p, " ", img.get_size())


func _wait(t: float) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < t * 1000.0:
		await process_frame


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else "."
	var lang: String = args[1] if args.size() > 1 else "en"
	var h: int = int(args[2]) if args.size() > 2 else 1280
	var only: String = args[3] if args.size() > 3 else ""
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(720, h)
	DisplayServer.window_set_size(Vector2i(720, h))
	await process_frame
	var settings = root.get_node("Settings")
	var cfg := OS.get_environment("TMPDIR").path_join("crossword-work/capture.cfg")
	DirAccess.make_dir_recursive_absolute(cfg.get_base_dir())
	DirAccess.remove_absolute(cfg)
	settings.path = cfg
	settings.load_settings()
	settings.set_language(lang)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	if only == "poster":
		await _poster()
	else:
		await _all()
	DirAccess.remove_absolute(cfg)
	quit(0)


## Fill a fraction of the white cells (entry by entry) with right letters.
func _partial(b: Board, keep: Array) -> void:
	for k in keep:
		for i in b.puzzle.entries[k].cells:
			b.letters[i] = b.puzzle.solution[i]


func _poster() -> void:
	var pick := int(OS.get_environment("CW_POSTER")) if OS.get_environment("CW_POSTER") != "" else 3
	main.open_puzzle(pick)
	var b: Board = main.board
	var n := b.puzzle.entries.size()
	_partial(b, [0, 2, n - 2])
	var target := 1
	b.go_entry(target)
	var cells: Array = b.puzzle.entries[target].cells
	b.letters[cells[0]] = b.puzzle.solution[cells[0]]
	b.cursor = cells[1]
	b.letters[cells[1]] = ""
	b.elapsed = 47.0
	# keep the key art inside the central ~80% of the width
	for side in ["margin_left", "margin_right"]:
		main._game.add_theme_constant_override(side, 72)
	main.refresh()
	await _shot("poster")


func _all() -> void:
	await _wait(0.3)
	await _shot("1-menu")
	main.open_puzzle(main.daily_index(), true)
	var b: Board = main.board
	_partial(b, [0, 1])
	b.letters[b.puzzle.entries[1].cells[1]] = "Q"
	b.go_entry(b.puzzle.entries.size() / 2 + 1)
	b.elapsed = 83.0
	main.refresh()
	await _shot("2-game")
	b.go_entry(1)
	b.cursor = b.puzzle.entries[1].cells[1]
	main.assist(true, false)
	main.show_assist()
	await _wait(0.4)
	await _shot("3-assist")
	main._close_overlay()
	# 7x7 puzzle
	for i in main.pack.size():
		if main.pack[i].width == 7:
			main.open_puzzle(i)
			_partial(main.board, [0, 3, 5])
			main.refresh()
			await _shot("4-seven")
			break
	main.open_puzzle(main.daily_index(), true)
	b = main.board
	for e in b.puzzle.entries:
		if e.dir == Puzzle.ACROSS:
			b.go_entry(b.puzzle.entries.find(e))
			for ch in e.answer:
				main.press_key(ch)
	await _wait(0.45)
	await _shot("5-wave")
	await _wait(1.0)
	await _shot("6-done")
	main.open_puzzle(2)
	main.press_key(main.board.current_clue().answer.substr(0, 1))
	main.save_now()
	main.show_list()
	await _shot("7-list")
	main.show_menu()
	main.show_howto()
	await _wait(0.4)
	await _shot("8-howto")
	main._close_overlay()
	await _shot("9-menu-after")
