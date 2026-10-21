extends SceneTree
## Hermetic poster capture (needs a display, not --headless):
##   godot --path . --resolution 720x1280 --script tools/poster.gd -- [out.png] [lang] [seed]
## Boots the real main scene, lets the greedy test bot play a real v2 game
## until the stack is busy (stone rows, holes, a few levels in) and its next
## placement clears something, makes that drop through the UI action and
## grabs the viewport mid-clear.

const Bot := preload("res://tests/prism_bot.gd")
const TEST_PATH := "user://poster_capture.cfg"
const RUN_PATH := "user://poster_run.cfg"


func _initialize() -> void:
	_run()


func _ready_to_shoot(b: PrismBoard) -> bool:
	if b.pieces_placed < 24 or b.stones() < 14 or b.filled() < 68 or b.stones_in > 4 or b.stones_in < 2:
		return false
	var best := Bot.best_placement(b)
	return not best.is_empty() and best.v > 120.0


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "poster.png"
	var lang: String = args[1] if args.size() > 1 else "en"
	var seed_value: int = int(args[2]) if args.size() > 2 else 11
	await process_frame
	var settings := root.get_node("Settings")
	settings.load_from(TEST_PATH)
	settings.set_language(lang)
	settings.best_score = 48210
	RunSave.path = RUN_PATH
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game(seed_value)
	for i in 3:
		await process_frame
	var b: PrismBoard = main.board
	var guard := 0
	while not _ready_to_shoot(b) and b.state == PrismBoard.State.PLAYING and guard < 600:
		var best := Bot.best_placement(b)
		if not best.is_empty():
			b.current.cells = best.cells
			b.current.pos.x = best.x
		b.hard_drop()
		if b.state == PrismBoard.State.RESOLVING:
			b.resolve_all()
		guard += 1
	print("poster: pieces=%d filled=%d stones=%d level=%d score=%d state=%d" % [
		b.pieces_placed, b.filled(), b.stones(), b.level, b.score, b.state])
	if b.state != PrismBoard.State.PLAYING:
		print("poster: game ended before a good frame; try another seed")
		quit(1)
		return
	main._last_level = b.level
	main._shown_score = b.score
	b.held = b.queue[2].duplicate_piece()
	main._update_hud()
	await process_frame
	var best := Bot.best_placement(b)
	b.current.cells = best.cells
	b.current.pos.x = best.x
	main._do("hard")
	var t := 0.0
	while t < 0.17:
		await process_frame
		t += main.get_process_delta_time()
	main.paused = true
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img.get_size() != Vector2i(720, 1280):
		img.resize(720, 1280, Image.INTERPOLATE_LANCZOS)
	img.save_png(out)
	print("poster: saved %s %s" % [out, img.get_size()])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	RunSave.clear()
	quit(0)
