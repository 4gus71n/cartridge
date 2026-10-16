extends SceneTree
## Desktop capture of the game-over screen (needs a display, not --headless):
##   godot --path . --resolution 720x1280 --script tools/capture_over.gd -- out.png [lang]
## A bot hard-drops real pieces until the game ends, then the overlay is grabbed.

const TEST_PATH := "user://capture_over.cfg"


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "over.png"
	var lang: String = args[1] if args.size() > 1 else "en"
	await process_frame
	var settings := root.get_node("Settings")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	settings.load_from(TEST_PATH)
	settings.set_language(lang)
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	Engine.time_scale = 6.0
	main.start_game(8)
	var drops := 0
	var frames := 0
	while main._overlay == null and frames < 30000:
		if main.board.state == PrismBoard.State.PLAYING:
			for k in (drops * 3 % 7) - 3:
				main._do("right")
			if drops % 3 == 1:
				main._do("rotate")
			main._do("hard")
			drops += 1
		await process_frame
		frames += 1
	Engine.time_scale = 1.0
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	print("capture_over: %s score=%d drops=%d" % [out, main.board.score, drops])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	quit(0)
