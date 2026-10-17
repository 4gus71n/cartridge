extends SceneTree
## UI bot: boots the real main scene and plays full games through the same
## entry points the buttons use: menu, 5 rounds (perfect, near, far, sea,
## wrong-country guesses), reveal card + per-photo credit, pause + save &
## exit + resume, summary map + best score, credits screen, language and
## units toggles, hit-target sizes, map/photo pan-zoom input.

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
	path = dir.path_join("pinpoint-work/ui_test.cfg")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	DirAccess.remove_absolute(path)
	var settings = root.get_node("Settings")
	settings.load_from(path)
	settings.miles = false
	settings.set_language("en")
	root.size = Vector2i(720, 1280)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred(settings)


func _frames(n := 3) -> void:
	for i in n:
		await process_frame


func _wait(t: float) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < t * 1000.0:
		await process_frame


func _run(settings) -> void:
	await _frames()
	check(main.phase == main.Phase.MENU, "boots into the menu")
	check(_find_button(main._menu, tr("PLAY")) != null, "menu has Play")
	_targets(main._menu, "menu")
	await _full_game(settings, true)
	await _pause_resume(settings)
	await _credits()
	await _toggles(settings)
	await _input_gestures()
	await _full_game(settings, false)
	DirAccess.remove_absolute(path)
	print("ui_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _targets(node: Node, where: String) -> void:
	for b in _buttons(node):
		if b.is_visible_in_tree():
			check(b.size.y >= 88.0 and b.size.x >= 88.0, "%s button '%s' >= 88 px (%s)" % [where, b.text, b.size])


## good=true: aim at the truth; otherwise mix of sea / wrong-country guesses.
func _full_game(settings, good: bool) -> void:
	var before_games: int = settings.games_played
	main.start_game(11 if good else 23)
	await _frames()
	check(main.phase == main.Phase.GUESS, "game starts in GUESS")
	check(main._photo.texture != null, "round photo loaded")
	check(main._confirm.disabled, "confirm disabled before a pin")
	_targets(main._game, "game")
	check(main._round_label.text == tr("ROUND") % [1, 5], "round label: " + main._round_label.text)
	check(not settings.saved_game.is_empty(), "game saved at start")
	var ids: Array[String] = main.game.photo_ids.duplicate()
	var uniq := {}
	for id in ids:
		uniq[id] = true
	check(uniq.size() == 5, "5 distinct photos")
	for i in 5:
		var photo: Dictionary = main.deck.by_id[main.game.current_id()]
		var truth := PhotoDeck.geo_of(photo)
		var guess := truth
		if not good:
			guess = [Vector2(-30, 30), truth + Vector2(25, 0), Vector2(truth.x, -truth.y * 0.5), truth + Vector2(0.01, 0.01), Vector2(-150, -10)][i]
		main.confirm_guess()
		check(main.phase == main.Phase.GUESS, "confirm without a pin does nothing")
		main.drop_pin(guess)
		await _frames(1)
		check(not main._confirm.disabled and main._confirm.text == tr("CONFIRM"), "confirm enabled after pin")
		await main.confirm_guess()
		await _frames()
		check(main.phase == main.Phase.REVEAL, "reveal after confirm")
		var r: Dictionary = main.last_result
		check(main._map.has_truth and main._map.has_guess, "map shows guess + truth")
		var credit: Label = main._bottom.find_child("Credit", true, false)
		check(credit != null and credit.text.find(String(photo.author)) >= 0 and credit.text.find(String(photo.license)) >= 0, "per-photo credit shown")
		if good:
			check(int(r.points) == 6000, "perfect guess scores 6000 (%d)" % r.points)
		elif i == 0:
			check(not r.country_ok and String(r.guess_country) == "", "sea guess: no bonus")
		elif i == 3:
			check(r.country_ok or String(photo.country) == "", "tiny offset keeps the country")
		_targets(main._game, "reveal")
		check(_find_button(main._game, tr("SEE_RESULTS") if i == 4 else tr("NEXT")) != null, "next button label round %d" % i)
		if i == 1:
			main.toggle_map_size()
			await _frames()
			check(main.map_big == false, "map can be shrunk at reveal")
			main.toggle_map_size()
		await _wait(0.3)
		main.next_round()
		await _frames()
	check(main.phase == main.Phase.SUMMARY, "summary after 5 rounds")
	await _wait(0.2)
	var total: int = main.game.total()
	check(settings.games_played == before_games + 1, "game counted")
	check(settings.saved_game.is_empty(), "saved game cleared at the end")
	if good:
		check(total == 30000, "perfect game = 30,000 (%d)" % total)
		check(main.record and settings.best_score == 30000, "best score saved")
		check(_find_label(main._summary, tr("NEW_BEST")) != null, "new best shown")
	else:
		check(total < 30000, "imperfect game < 30,000 (%d)" % total)
		check(not main.record and settings.best_score == 30000, "best kept")
	check(_find_label(main._summary, GeoMath.group_digits(total)) != null, "total shown")
	check(main._map.pairs.size() == 5, "summary map shows 5 guess/truth pairs")
	_targets(main._summary, "summary")
	main.show_menu()
	await _frames()


func _pause_resume(settings) -> void:
	main.start_game(5)
	await _frames()
	var first: String = main.game.current_id()
	main.drop_pin(Vector2(0, 0))
	await main.confirm_guess()
	main.next_round()
	await _frames()
	main.pause()
	await _frames()
	check(main.has_overlay(), "pause overlay")
	_targets(main._overlay, "pause")
	main.resume_from_pause()
	await _frames()
	check(not main.has_overlay(), "continue closes overlay")
	main.pause()
	main.exit_to_menu()
	await _frames()
	check(main.phase == main.Phase.MENU, "save & exit goes to menu")
	check(main.has_resume(), "menu offers resume")
	check(_find_button(main._menu, tr("RESUME") % [2, 5]) != null, "resume button shows round 2/5")
	# Simulate an app restart: reload settings from disk.
	settings.saved_game = {}
	settings.load_from(path)
	main.show_menu()
	await _frames()
	check(main.has_resume(), "resume survives a restart")
	main.resume_game()
	await _frames()
	check(main.game.round_index() == 1 and main.game.photo_ids[0] == first, "resumed at round 2 of the same game")
	check(main.phase == main.Phase.GUESS, "resumed in GUESS")
	main.exit_to_menu()
	await _frames()
	main.start_game(6)  # New game replaces the saved one.
	await _frames()
	check(main.game.round_index() == 0, "new game starts fresh")
	main.show_menu()
	await _frames()


func _credits() -> void:
	main.show_credits()
	await _frames()
	check(main.phase == main.Phase.CREDITS, "credits screen")
	var labels := 0
	for l in main._credits.find_children("*", "Label", true, false):
		if l.text.find("commons.wikimedia.org/wiki/File:") >= 0:
			labels += 1
	check(labels == main.deck.photos.size(), "credits list every photo (%d)" % labels)
	check(_find_label(main._credits, tr("CREDITS_MAP")) != null, "map credit shown")
	_targets(main._credits, "credits")
	main.show_menu()
	await _frames()


func _toggles(settings) -> void:
	var units: Button = main._menu.find_child("Units", true, false)
	units.pressed.emit()
	await _frames()
	check(settings.miles, "units toggled to miles")
	var lang: Button = main._menu.find_child("Language", true, false)
	lang.pressed.emit()
	await _frames()
	check(settings.language == "es" and tr("PLAY") == "Jugar", "language toggled to Spanish")
	main.start_game(8)
	await _frames()
	main.drop_pin(Vector2(0, 0))
	await main.confirm_guess()
	await _frames()
	var txt := ""
	for l in main._bottom.find_children("*", "Label", true, false):
		txt += l.text + "|"
	check(txt.find(" mi") >= 0, "distance in miles: " + txt)
	check(txt.find("Foto:") >= 0, "Spanish credit line")
	main.exit_to_menu()
	await _frames()
	(main._menu.find_child("Language", true, false) as Button).pressed.emit()
	await _frames()
	(main._menu.find_child("Units", true, false) as Button).pressed.emit()
	await _frames()
	check(settings.language == "en" and not settings.miles, "toggles restored")
	main.start_game(9)
	await _frames()
	main.exit_to_menu()
	await _frames()


func _input_gestures() -> void:
	main.start_game(3)
	await _frames(4)
	var map: MapView = main._map
	var z0 := map.zoom
	map.zoom_step(2.0)
	check(map.zoom > z0 * 1.9, "zoom button zooms the map")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = map.size / 2.0
	var z1 := map.zoom
	map._gui_input(wheel)
	check(map.zoom > z1, "mouse wheel zooms the map")
	# Pinch: two touches moving apart.
	var z2 := map.zoom
	_touch(map, 0, Vector2(300, 200), true)
	_touch(map, 1, Vector2(400, 200), true)
	_drag(map, 1, Vector2(500, 200), Vector2(100, 0))
	_touch(map, 1, Vector2(500, 200), false)
	_touch(map, 0, Vector2(300, 200), false)
	check(map.zoom > z2 * 1.5, "pinch zooms the map (%.3f -> %.3f)" % [z2, map.zoom])
	check(not map.has_guess, "pinch does not drop a pin")
	# Drag pans without dropping a pin.
	var off := map.offset
	_touch(map, 0, Vector2(300, 200), true)
	_drag(map, 0, Vector2(360, 230), Vector2(60, 30))
	_touch(map, 0, Vector2(360, 230), false)
	check(map.offset.distance_to(off) > 30.0, "drag pans the map")
	check(not map.has_guess, "drag does not drop a pin")
	# A tap (even a slow one) drops the pin where tapped.
	_touch(map, 0, Vector2(250, 150), true)
	await _wait(0.6)
	_touch(map, 0, Vector2(252, 151), false)
	check(map.has_guess and not main._confirm.disabled, "tap drops a pin and enables confirm")
	var expect := map.screen_to_geo(Vector2(252, 151))
	check(map.guess.distance_to(expect) < 1.0, "pin lands under the finger")
	# Photo: wheel zooms, double tap zooms in.
	var photo: PhotoView = main._photo
	var pz := photo.zoom
	wheel.position = photo.size / 2.0
	photo._gui_input(wheel)
	check(photo.zoom > pz, "mouse wheel zooms the photo")
	photo.reset_view()
	check(photo.zoom >= photo.fit_zoom() - 1e-4, "photo never zooms out past fit")
	main.exit_to_menu()
	await _frames()


func _touch(c: Control, idx: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = pos
	e.pressed = pressed
	c._gui_input(e)


func _drag(c: Control, idx: int, pos: Vector2, rel: Vector2) -> void:
	var steps := 5
	for k in steps:
		var e := InputEventScreenDrag.new()
		e.index = idx
		e.relative = rel / steps
		e.position = pos - rel + rel * float(k + 1) / steps
		c._gui_input(e)


func _buttons(node: Node) -> Array:
	return node.find_children("*", "Button", true, false)


func _find_button(node: Node, text: String) -> Button:
	for b in _buttons(node):
		if b.text == text:
			return b
	return null


func _find_label(node: Node, text: String) -> Label:
	for l in node.find_children("*", "Label", true, false):
		if l.text == text:
			return l
	return null
