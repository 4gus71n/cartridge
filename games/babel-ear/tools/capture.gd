extends SceneTree
## Hermetic screenshots (needs a display, not --headless):
##   godot --path . --script tools/capture.gd -- <out_dir> [lang] [height] [poster]
## Without "poster": menu / listen / reveal / pause / summary / credits PNGs.
## With "poster": only <out_dir>/poster.png, a round in progress (Hard mode,
## clip half played, waveform lit) staged on a fixed seed.

const TEST_PATH := "user://capture_settings.cfg"

var main: Control
var out_dir := ""


func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	for k in 3:
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
	var poster := args.size() > 3 and args[3] == "poster"
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(720, h)
	DisplayServer.window_set_size(Vector2i(720, h))
	await process_frame
	var settings = root.get_node("Settings")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	settings.load_from(TEST_PATH)
	settings.best = {"easy": 2650, "hard": 3150}
	settings.set_language(lang)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(0.6)
	if poster:
		await _poster()
	else:
		await _all()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	quit(0)


func _play_rounds(n: int, wrong_at := -1) -> void:
	for i in n:
		var truth: String = main.game.truth_of(main.game.round_index(), main.bank)
		var pick := truth
		if i == wrong_at:
			for c in main.game.current_choices():
				if c != truth:
					pick = c
					break
		main.play_clip()
		main.choose(pick)
		main.next_round()
		await _wait(0.05)


func _freeze_playback(frac: float) -> void:
	# Show a clip "mid-play" without depending on the audio clock.
	main.play_clip()
	main._player.stop()
	main._player.volume_db = -80.0
	main._play_start_ms = Time.get_ticks_msec() - int(frac * main._clip_len * 1000.0)
	main.set_process(false)
	main._wave.progress = frac
	main._wave.playing = true
	main._play_btn.kind = "stop"
	main._hint.text = tr("LISTENING")


func _poster() -> void:
	main.audio_unlocked = true
	main.start_game(BabelGame.HARD, 4)
	main._player.volume_db = -80.0
	await _play_rounds(3)
	await _wait(0.6)
	_freeze_playback(0.56)
	await _wait(0.6)
	await _shot("poster")


func _all() -> void:
	await _shot("1-menu")
	main.start_game(BabelGame.EASY, 11)
	main._player.volume_db = -80.0
	await _wait(0.4)
	await _shot("2-listen-first")
	await _play_rounds(2)
	_freeze_playback(0.42)
	await _wait(0.3)
	await _shot("3-listen")
	main.set_process(true)
	main.choose(main.game.current_choices()[0])
	await _wait(0.6)
	await _shot("4-reveal")
	main.pause()
	await _wait(0.3)
	await _shot("5-pause")
	main._close_overlay()
	main.next_round()
	await _play_rounds(10 - main.game.round_index(), 2)
	await _wait(0.8)
	await _shot("6-summary")
	main.show_credits()
	await _wait(0.4)
	await _shot("7-credits")
	main.show_menu()
	main.start_game(BabelGame.HARD, 21)
	main.play_clip()
	main.choose(main.game.truth_of(0, main.bank))
	await _wait(0.6)
	await _shot("8-hard-reveal")
