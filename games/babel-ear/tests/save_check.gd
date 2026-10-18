extends SceneTree
## Settings persistence: language, best score per mode, games played, recent
## clips (capped), in-progress game; corrupt/missing files fall back cleanly.

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var dir := OS.get_environment("TMPDIR")
	if dir == "":
		dir = OS.get_user_data_dir()
	var path := dir.path_join("babel-work/save_test.cfg")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	DirAccess.remove_absolute(path)
	var s = root.get_node("Settings")
	s.load_from(path)
	check(s.best_for("easy") == 0 and s.best_for("hard") == 0, "fresh: no bests")
	check(s.saved_game.is_empty() and s.recent.is_empty(), "fresh: no game, no recent")
	s.set_language("es")
	check(TranslationServer.get_locale().begins_with("es"), "language applies to locale")
	check(s.submit_score("easy", 1200), "first easy score is a record")
	check(not s.submit_score("easy", 900), "lower score is not a record")
	check(s.submit_score("hard", 300), "hard has its own best")
	check(s.best_for("easy") == 1200 and s.best_for("hard") == 300, "bests per mode")
	var ids := []
	for i in 70:
		ids.append("x_%d" % i)
	s.mark_heard(ids)
	s.mark_heard(["x_20"])
	check(s.recent.size() == s.RECENT_MAX, "recent capped at %d" % s.RECENT_MAX)
	check(s.recent[-1] == "x_20" and not ("x_0" in s.recent), "recent keeps newest, drops oldest")
	var bank := ClipBank.load_default()
	var g := BabelGame.create(bank, BabelGame.HARD, 4242)
	g.answer(g.truth_of(0, bank), bank)
	s.save_game(g.to_dict())

	s.load_from(path)  # reload from disk
	check(s.language == "es", "language persisted")
	check(s.best_for("easy") == 1200 and s.best_for("hard") == 300, "bests persisted")
	check(s.games_played == 3, "games played persisted (%d)" % s.games_played)
	check(s.recent.size() == s.RECENT_MAX and s.recent[-1] == "x_20", "recent persisted")
	var back := BabelGame.from_dict(s.saved_game, bank)
	check(back != null and back.clip_ids == g.clip_ids and back.round_index() == 1 and back.score == g.score,
		"in-progress game persisted and restorable")
	check(s.submit_score("hard", 100) == false and s.saved_game.is_empty(), "finishing a game clears the saved game")

	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("[records]\nbest_easy=\"garbage\"\nrecent=7\n[game]\nsaved=3\n")
	f.close()
	s.load_from(path)
	check(s.best_for("easy") == 0 and s.recent.is_empty() and s.saved_game.is_empty(), "malformed values fall back")
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("not a config file ][")
	f.close()
	s.load_from(path)
	check(s.best_for("hard") == 0 and s.language in ["en", "es"], "corrupt file falls back to defaults")
	DirAccess.remove_absolute(path)
	print("save_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
