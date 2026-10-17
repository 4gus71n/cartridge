extends SceneTree
## Hermetic screenshots (needs a display, not --headless):
##   godot --path . --script tools/capture.gd -- <out_dir> [lang] [height] [poster_photo_id]
## Without a photo id: menu / guess / reveal / pause / summary / credits PNGs.
## With one: only <out_dir>/poster.png, a staged reveal of that photo
## (photo on top, map with the guess -> truth line below).

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
	var poster: String = args[3] if args.size() > 3 else ""
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(720, h)
	DisplayServer.window_set_size(Vector2i(720, h))
	await process_frame
	var settings = root.get_node("Settings")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	settings.load_from(TEST_PATH)
	settings.best_score = 21480
	settings.miles = false
	settings.set_language(lang)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(0.5)
	if poster != "":
		await _poster(poster)
	else:
		await _all()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	quit(0)


func _stage(id: String, guess_offset: Vector2) -> void:
	main.start_game(4)
	if id != "" and main.deck.by_id.has(id):
		main.game.photo_ids[0] = id
		main._begin_round()
	await _wait(0.6)
	var truth := PhotoDeck.geo_of(main.deck.by_id[main.game.current_id()])
	main.drop_pin(truth + guess_offset)


func _poster(id: String) -> void:
	await _stage(id, Vector2(38.0, -10.0))
	await main.confirm_guess()
	await _wait(2.2)
	main._set_map_big(false)  # poster: photo on top, reveal line below
	await _wait(0.3)
	var truth := PhotoDeck.geo_of(main.deck.by_id[id])
	var pts: Array[Vector2] = [truth, truth + Vector2(38.0, -10.0)]
	main._map.frame_points(pts, 0.0)
	await _wait(0.2)
	main._map.zoom_step(0.55)
	await _wait(1.0)
	await _shot("poster")


func _all() -> void:
	await _shot("1-menu")
	await _stage("", Vector2(-14, 9))
	await _wait(0.3)
	await _shot("2-guess")
	await main.confirm_guess()
	await _wait(2.0)
	await _shot("3-reveal")
	main.pause()
	await _wait(0.4)
	await _shot("4-pause")
	main.resume_from_pause()
	for i in 4:
		main.next_round()
		await _wait(0.4)
		var truth := PhotoDeck.geo_of(main.deck.by_id[main.game.current_id()])
		main.drop_pin(truth + Vector2(i * 3 - 4, 2 - i))
		await main.confirm_guess()
		await _wait(0.2)
	main.next_round()
	await _wait(1.2)
	await _shot("5-summary")
	main.show_credits()
	await _wait(0.4)
	await _shot("6-credits")
