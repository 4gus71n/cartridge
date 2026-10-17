extends SceneTree
## Hermetic poster capture (needs a display, not --headless):
##   godot --path . --script tools/poster.gd -- [out.png] [lang]
## Boots the real main scene with a narrower column (key art in the central
## ~80 % of the width), stages a real mid-game Medium board with entries,
## a hint and pencil marks (true candidates), selects a cell so the
## same-digit / row / column / box highlights show, and grabs the viewport.

const TEST_PATH := "user://poster_capture.cfg"


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "poster.png"
	var lang: String = args[1] if args.size() > 1 else "en"
	root.size = Vector2i(720, 1280)
	await process_frame # let the Settings autoload run _ready() first
	var settings := root.get_node("Settings")
	settings.load_from(TEST_PATH)
	settings.set_language(lang)
	var main: Control = load("res://scenes/main.tscn").instantiate()
	main.side_margin = 72.0
	root.add_child(main)
	await process_frame
	main.start_game(SudokuGame.MEDIUM, 4242)
	var g: SudokuGame = main.game
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var empties := []
	for i in 81:
		if g.values[i] == 0:
			empties.append(i)
	empties = SudokuGenerator.shuffled(empties, rng)
	# Fill ~40 % of the open cells correctly, one by hint.
	var fill := int(empties.size() * 0.4)
	for k in fill:
		var i: int = empties[k]
		if k == 3:
			g.hint(i)
		else:
			g.set_value(i, g.solution[i])
	# Pencil marks: real candidates on the cells that have 2-4 of them.
	var marked := 0
	for k in range(fill, empties.size()):
		var i: int = empties[k]
		var m := g._candidates(i)
		var n: int = SudokuGrid.POP[m]
		if n >= 2 and n <= 4 and marked < 16:
			g.notes[i] = m
			marked += 1
	g.elapsed = 4 * 60 + 27
	g.mistakes = 0
	# Select a player-entered cell whose digit also appears as a pencil mark.
	var sel := -1
	for k in range(fill - 1, -1, -1):
		var i: int = empties[k]
		if g.hinted[i] == 1:
			continue
		var bit := 1 << g.values[i]
		var hits := 0
		for j in 81:
			if g.notes[j] & bit:
				hits += 1
		if hits >= 2 and SudokuGrid.row(i) >= 2 and SudokuGrid.row(i) <= 6:
			sel = i
			break
	main.press_cell(sel if sel >= 0 else empties[0])
	main._refresh()
	print("poster: %d filled, %d marked, selected %d" % [fill, marked, sel])
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img.get_size() != Vector2i(720, 1280):
		img.resize(720, 1280, Image.INTERPOLATE_LANCZOS)
	img.save_png(out)
	print("poster: saved %s %s" % [out, img.get_size()])
	settings.clear_game()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	quit(0)
