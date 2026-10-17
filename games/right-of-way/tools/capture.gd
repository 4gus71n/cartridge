extends SceneTree
## Hermetic screenshots of every screen (needs a display, not --headless):
##   godot --path . --script tools/capture.gd -- <out_dir> [lang] [height] [only]
## Saves menu / game / reveal / feedback / pause / over / learn / detail PNGs
## at 720 x <height> (default 1280). `only` = "poster" writes just
## <out_dir>/poster.png: a staged mid-run frame (sign + choices + timer bar).

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
	var only: String = args[3] if args.size() > 3 else ""
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(720, h)
	DisplayServer.window_set_size(Vector2i(720, h))
	await process_frame
	var settings = root.get_node("Settings")
	settings.path = TEST_PATH
	settings.best_score = 0
	settings.set_language(lang)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	if only == "poster":
		await _poster()
	else:
		await _all()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	quit(0)


func _poster() -> void:
	root.get_node("Settings").best_score = 14250
	main.start_run(7)
	# Play a believable streak through the real API (mostly fast answers).
	for i in 11:
		main._process(0.35 + 0.15 * (i % 3))
		main.answer(main.question.answer)
		main._process(1.0)
	main.run.lives = 2
	_force_question(OS.get_environment("ROW_POSTER_SIGN") if OS.get_environment("ROW_POSTER_SIGN") != "" else "children")
	await _wait(0.5)
	for l in main._road.get_children():
		if l is Label:
			l.queue_free()
	main.time_left = main.time_limit * 0.46
	main._timer.ratio = 0.46
	main.paused = true
	main._update_hud()
	await _shot("poster")


## Replace the current question with `id` (keeps choices real + distinct).
func _force_question(id: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var q := SignQuiz.build_question(id, 4, rng)
	main.question = q
	main._road.sign_view.sign_id = id
	for i in main._choice_buttons.size():
		main._choice_buttons[i].text = TranslationServer.translate(SignCatalog.action_key(q.choices[i]))


func _all() -> void:
	await _wait(0.6)
	await _shot("1-menu")
	main.start_run(11)
	await _wait(0.6)
	await _shot("2-game")
	main.answer(main.question.answer)
	await _wait(0.15)
	await _shot("3-correct")
	await _wait(0.6)
	# Pick a wrong answer.
	var wrong: int = (main.question.answer + 1) % main.question.choices.size()
	main.answer(wrong)
	await _wait(0.2)
	await _shot("4-wrong")
	await _wait(0.9)
	await _shot("5-feedback")
	main.advance()
	await _wait(0.4)
	main.pause()
	await _wait(0.3)
	await _shot("6-pause")
	main.resume()
	# Run out the clock twice to finish the run.
	for k in 2:
		main.time_left = 0.01
		main._intro = 0.0
		await _wait(1.2)
		if k == 0:
			main.advance()
			await _wait(0.4)
	await _shot("7-timeout")
	main.advance()
	await _wait(0.5)
	await _shot("8-over")
	main.review_missed()
	await _wait(0.5)
	await _shot("9-detail")
	main._close_overlay()
	await _wait(0.2)
	await _shot("10-learn")
	# longest explanation for overflow checks
	var longest := ""
	var n := 0
	for id in SignCatalog.ids():
		var l: int = TranslationServer.translate(SignCatalog.explain_key(id)).length() + TranslationServer.translate(SignCatalog.name_key(id)).length()
		if l > n:
			n = l
			longest = id
	main.open_detail(SignCatalog.ids(), SignCatalog.index_of(longest))
	await _wait(0.4)
	await _shot("11-detail-longest")
