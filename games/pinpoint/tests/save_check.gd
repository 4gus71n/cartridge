extends SceneTree
## Game state + persistence: scoring a game, serialise/resume, Settings
## save/load round trip (best score, units, language, recent, saved game).

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	_game()
	_settings()
	print("save_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _game() -> void:
	var g := PinpointGame.new()
	var ids: Array[String] = ["a", "b", "c", "d", "e"]
	g.start(ids)
	check(g.round_index() == 0 and g.current_id() == "a" and not g.is_over(), "fresh game at round 0")
	var r := g.submit(Vector2(2.35, 48.86), "FRA", Vector2(2.35, 48.86), "FRA")
	check(int(r.points) == 6000 and r.country_ok, "perfect guess = 6000")
	r = g.submit(Vector2(-0.13, 51.5), "GBR", Vector2(2.35, 48.86), "FRA")
	check(not r.country_ok and int(r.points) == GeoMath.distance_points(float(r.km)), "wrong country, distance only")
	check(int(r.points) > 4000 and int(r.points) < 5000, "London for Paris ~4.2k (%d)" % r.points)
	r = g.submit(Vector2(-30, 30), "", Vector2(-30.1, 30.1), "")
	check(not r.country_ok, "sea never earns the country bonus")
	var d := g.to_dict()
	var json := JSON.stringify(d)
	var back := PinpointGame.from_dict(JSON.parse_string(json))
	check(back.round_index() == 3 and back.current_id() == "d", "resume from JSON at round 3")
	check(back.total() == g.total(), "total survives serialisation (%d)" % back.total())
	check(PinpointGame.guess_of(back.results[1]).distance_to(Vector2(-0.13, 51.5)) < 1e-4, "guess survives")
	g.submit(Vector2(0, 0), "", Vector2(10, 10), "")
	g.submit(Vector2(0, 0), "", Vector2(10, 10), "")
	check(g.is_over() and g.current_id() == "", "over after 5 rounds")
	check(g.total() <= 5 * GeoMath.ROUND_MAX, "total within max")


func _settings() -> void:
	var s = root.get_node("Settings")
	var dir := OS.get_environment("TMPDIR")
	if dir == "":
		dir = OS.get_user_data_dir()
	var path := dir.path_join("pinpoint-work/save_test.cfg")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	DirAccess.remove_absolute(path)
	s.load_from(path)
	check(s.best_score == 0 and s.games_played == 0, "fresh profile")
	check(s.submit_score(12000), "first score is a record")
	check(not s.submit_score(9000), "lower score is not a record")
	check(s.submit_score(15000), "higher score is a record")
	s.miles = false
	s.toggle_units()
	s.set_language("es")
	var ids: Array = []
	for i in 100:
		ids.append("p%d" % i)
	s.mark_seen(ids)
	check(s.recent.size() == s.RECENT_MAX, "recent capped at %d" % s.RECENT_MAX)
	check(s.recent[-1] == "p99" and not "p0" in s.recent, "recent keeps the newest")
	var g := PinpointGame.new()
	var gids: Array[String] = ["p1", "p2", "p3", "p4", "p5"]
	g.start(gids)
	g.submit(Vector2(1, 1), "", Vector2(2, 2), "")
	s.save_game(g.to_dict())
	# Reload from disk into a clean state.
	s.best_score = 0
	s.games_played = 0
	s.miles = false
	s.recent = []
	s.saved_game = {}
	s.load_from(path)
	check(s.best_score == 15000, "best score persisted (%d)" % s.best_score)
	check(s.games_played == 3, "games played persisted")
	check(s.miles == true, "units persisted")
	check(s.language == "es" and TranslationServer.get_locale().begins_with("es"), "language persisted + applied")
	check(s.recent.size() == s.RECENT_MAX, "recent persisted")
	var resumed := PinpointGame.from_dict(s.saved_game)
	check(resumed.round_index() == 1 and resumed.photo_ids.size() == 5, "saved game persisted")
	s.save_game({})
	s.load_from(path)
	check(s.saved_game.is_empty(), "cleared saved game persisted")
	s.set_language("en")
	DirAccess.remove_absolute(path)
