extends SceneTree
## UI-level bot: boots the real main scene and drives it through the same
## entry points touch input uses (buttons, map tap/swipe/long-press signals):
## menu EN/ES, new run, moves, travel, inspect, pack (eat, throw), map,
## pause -> menu -> continue (autosave), stairs, death and victory screens,
## high-score table, and translation coverage of every text key.
## godot --headless --path . --script tests/ui_check.gd

const TEST_PATH := "user://ui_check_test.cfg"

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _texts(n: Node, out: Array) -> Array:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return out
	if n is Label or n is Button:
		out.append(n.text)
	for c in n.get_children():
		_texts(c, out)
	return out


func _has_text(main: Node, part: String) -> bool:
	for t in _texts(main, []):
		if str(t).contains(part):
			return true
	return false


func _find(n: Node, node_name: String) -> Node:
	return n.find_child(node_name, true, false)


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _until(cond: Callable, max_frames := 300) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func _press(main: Node, node_name: String) -> void:
	var b := _find(main, node_name) as Button
	if b == null:
		check(false, "button %s exists" % node_name)
		return
	b.pressed.emit()
	await _frames(2)


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	_coverage()
	var settings := root.get_node("Settings")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	settings.load_from(TEST_PATH)
	settings.clear_run()
	settings.set_language("en")
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	check(_has_text(main, "DELVE") and _has_text(main, "New run"), "menu shows title + new run")
	check(_find(main, "Continue") == null, "no Continue without a save")
	check(_has_text(main, "No runs yet"), "empty high-score table")
	await _press(main, "Language")
	check(_has_text(main, "Nueva partida") and _has_text(main, "English"), "menu translated to ES")
	await _press(main, "Language")
	await _press(main, "HowTo")
	check(main.overlay_kind() == "help" and _has_text(main, "Heart of Embers"), "how-to-play opens")
	await _press(main, "Close")

	# --- new run ---
	await _press(main, "NewRun")
	check(await _until(func() -> bool: return main.run != null and not main.busy), "new run generated")
	var r: Run = main.run
	check(r.depth == 1 and r.state == "play" and main.map_view.is_visible_in_tree(), "playing depth 1")
	var wait_btn := _find(main, "Act_wait") as Control
	check(wait_btn.size.x >= 88.0 and wait_btn.size.y >= 88.0, "action buttons >= 88 px (%s)" % wait_btn.size)
	check((_find(main, "MenuBtn") as Control).size.x >= 88.0, "menu button >= 88 px")
	check(main.map_view.tile >= 54.0 and main.map_view.tile <= 66.0, "camera ~12 tiles wide (tile %.0f)" % main.map_view.tile)
	check(settings.has_run(), "run autosaved at start")
	# Tap an adjacent open cell.
	var t0 := r.turns
	var step := Vector2i.ZERO
	for d: Vector2i in Pathing.DIRS:
		var c := Vector2i(r.px, r.py) + d
		var tt := r.lv.tile(c.x, c.y)
		if (tt == Level.FLOOR or tt == Level.CORRIDOR) and r.lv.monster_at(c.x, c.y).is_empty():
			step = d
			break
	main.map_view.tapped.emit(Vector2i(r.px, r.py) + step)
	await _frames(2)
	check(r.turns == t0 + 1, "tapping an adjacent tile takes a turn")
	check(int(settings.saved_run().turns) == r.turns, "autosave after every turn")
	main.map_view.swiped.emit(-step)
	await _frames(2)
	check(r.turns == t0 + 2, "swipe takes a single step")
	# Travel to a far known cell.
	var dist := Pathing.distance_map(r.lv, r.px, r.py, true)
	var far := Vector2i(-1, -1)
	for i in dist.size():
		if dist[i] >= 4 and r.lv.tiles[i] == Level.FLOOR:
			far = Vector2i(i % Level.W, i / Level.W)
			break
	if far.x >= 0:
		var start := Vector2i(r.px, r.py)
		check(main.travel_to(far), "travel path found")
		for k in 60:
			if main.travel.is_empty():
				break
			await main.travel_step()
		check(Vector2i(r.px, r.py) != start, "tap-to-travel walks the path")
	# Long-press inspect.
	main.map_view.held.emit(Vector2i(r.px, r.py))
	await _frames(1)
	check(main.inspect_text().begins_with("You"), "long-press inspects (%s)" % main.inspect_text())

	# --- pack: eat, throw ---
	r.hunger = 200
	await _press(main, "Act_pack")
	check(main.overlay_kind() == "inventory" and _has_text(main, "Pack 4/18"), "pack opens with starting kit")
	var food := -1
	var darts := -1
	for i in r.inv.size():
		if r.inv[i].id == "ration":
			food = i
		if r.inv[i].id == "darts":
			darts = i
	main.select_item(food)
	await _frames(2)
	check(_has_text(main, "Eat"), "food offers Eat")
	await _press(main, "ActPrimary")
	check(r.hunger > 900 and main.overlay_kind() == "", "eating from the pack works")
	var nd := int(r.inv[darts].n)
	await _press(main, "Act_pack")
	main.select_item(darts)
	await _frames(2)
	await _press(main, "ActThrow")
	check(main.aim_kind == "throw", "throw enters aim mode")
	var tgt := Vector2i(r.px, r.py)
	for d: Vector2i in Pathing.DIRS:
		if r.lv.passable(r.px + d.x, r.py + d.y) and not r.lv.solid(r.px + d.x, r.py + d.y):
			tgt = Vector2i(r.px, r.py) + d * 2
			break
	main.map_view.tapped.emit(tgt)
	await _frames(2)
	check(int(r.inv[darts].n) == nd - 1 and main.aim_kind == "", "tapping a target throws a dart")
	# Map overlay.
	await _press(main, "Act_map")
	check(main.overlay_kind() == "map", "map overlay opens")
	main._close_overlay()
	await _frames(1)

	# --- pause -> menu -> continue ---
	var turns := r.turns
	await _press(main, "MenuBtn")
	check(main.overlay_kind() == "pause", "pause menu opens")
	await _press(main, "ToMenu")
	check(_find(main, "Continue") != null and _has_text(main, "Depth 1"), "menu offers Continue with run info")
	await _press(main, "Continue")
	r = main.run
	check(r != null and r.turns == turns and main.map_view.is_visible_in_tree(), "Continue resumes the saved run")

	# --- stairs ---
	r.px = r.lv.stairs.x
	r.py = r.lv.stairs.y
	r.update_fov()
	main._refresh()
	check(not (_find(main, "Act_stairs") as Button).disabled, "Stairs button enabled on stairs")
	await _press(main, "Act_stairs")
	check(await _until(func() -> bool: return r.depth == 2 and not main.busy), "descending generates depth 2")
	check(int(settings.saved_run().depth) == 2, "autosave on the new floor")

	# --- death ---
	var ogre := Spawn.monster("ogre", r.px + 1, r.py, r.rng)
	if not r.lv.passable(r.px + 1, r.py):
		ogre.x = r.px - 1
	r.lv.tiles[Level.idx(ogre.x, ogre.y)] = Level.FLOOR
	ogre.aw = true
	r.lv.monsters.append(ogre)
	r.hp = 1
	for k in 60:
		if r.state != "play":
			break
		await _press(main, "Act_wait")
	check(r.state == "dead", "player can die")
	await _frames(2)
	check(main.overlay_kind() == "end" and _has_text(main, "YOU DIED"), "death screen shown")
	check(_has_text(main, "Slain by the ogre on depth 2"), "death screen names cause + depth")
	check(_has_text(main, "Score") and _has_text(main, "New high score!"), "score + record shown")
	check(not settings.has_run() and settings.scores.size() == 1, "save cleared, score recorded")
	main.end_button(false, true)
	await _frames(2)
	check(_has_text(main, "ogre") and _find(main, "Continue") == null, "menu lists the death in high scores")

	# --- victory (ES) ---
	settings.set_language("es")
	main.start_new(4242)
	check(await _until(func() -> bool: return main.run != null and not main.busy), "second run generated")
	r = main.run
	var spot := Vector2i(-1, -1)
	for d: Vector2i in Pathing.DIRS:
		var c := Vector2i(r.px, r.py) + d
		if r.lv.tile(c.x, c.y) == Level.FLOOR and r.lv.monster_at(c.x, c.y).is_empty():
			spot = c
			break
	r.lv.items.append({"x": spot.x, "y": spot.y, "it": Spawn.item("amulet"), "s": true})
	main.map_view.tapped.emit(spot)
	await _frames(2)
	check(not (_find(main, "Act_grab") as Button).disabled, "Grab enabled on an item")
	main.map_view.tapped.emit(spot) # tap self = pick up
	await _frames(3)
	check(r.state == "won" and main.overlay_kind() == "end", "taking the amulet wins")
	check(_has_text(main, "HAS ESCAPADO") and _has_text(main, "Corazón de Ascuas"), "victory screen in ES")
	main.end_button(false, true)
	await _frames(2)
	check(_has_text(main, "Victoria") and settings.wins == 1, "victory recorded in ES menu")
	settings.set_language("en")
	print("ui_check: %d passed, %d failed" % [_pass, _fail])
	main.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings.run_path()))
	quit(1 if _fail > 0 else 0)


## Every literal or generated text key used by the scripts exists in EN and ES.
func _coverage() -> void:
	var keys := {}
	var re := RegEx.create_from_string("\"#([A-Z][A-Z0-9_]+)\"|\"f\": \"([A-Z][A-Z0-9_]+)\"|tr\\(\"([A-Z][A-Z0-9_]+)\"\\)")
	for f in DirAccess.get_files_at("res://scripts"):
		if not f.ends_with(".gd"):
			continue
		var src := FileAccess.get_file_as_string("res://scripts/" + f)
		for m in re.search_all(src):
			for g in [1, 2, 3]:
				var k := m.get_string(g)
				if k != "" and not k.ends_with("_") and k != "KEY":
					keys[k] = true
	for id in Defs.MONSTERS:
		keys["M_" + id.to_upper()] = true
		keys["MN_" + id.to_upper()] = true
		if Defs.MONSTERS[id].has("range"):
			keys["SHOOT_" + id.to_upper()] = true
	for id in Defs.ITEMS:
		keys["I_" + id.to_upper()] = true
		if Defs.cls(id) in ["potion", "scroll", "wand", "food"]:
			keys["D_" + id.to_upper()] = true
	for c in Defs.POTION_COLORS + Defs.WAND_WOODS:
		keys[c[0]] = true
	for t in Defs.TRAPS:
		keys["TRAP_" + t.to_upper()] = true
	for k in ["MSG_EAT_RATION", "MSG_EAT_APPLE", "D_UNK_POTION", "D_UNK_SCROLL", "D_UNK_WAND", "TR_PACK", "TR_POISON", "TR_DRAIN", "TR_REGEN", "TR_COWARD"]:
		keys[k] = true
	var missing := []
	for lang in ["en", "es"]:
		TranslationServer.set_locale(lang)
		for k in keys:
			if TranslationServer.translate(k) == k and k != "TITLE":
				missing.append(lang + ":" + k)
	TranslationServer.set_locale("en")
	check(missing.is_empty(), "all %d text keys translated (missing %s)" % [keys.size(), str(missing)])
