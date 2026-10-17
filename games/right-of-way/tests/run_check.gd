extends SceneTree
## Timer / score / streak / lives rules and best-score persistence.

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	_timer()
	_scoring()
	_lives()
	_save_load()
	print("run_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _timer() -> void:
	var r := RunState.new()
	check(is_equal_approx(r.time_limit(), 4.5), "starts at 4.5 s")
	var prev := r.time_limit()
	var monotonic := true
	for i in 40:
		r.answer_correct(r.time_limit())
		if r.time_limit() > prev + 0.0001:
			monotonic = false
		prev = r.time_limit()
	check(monotonic, "time limit never grows with the streak")
	check(is_equal_approx(r.time_limit(), 2.0), "floors at 2.0 s (%.2f)" % r.time_limit())
	r.streak = 20
	check(is_equal_approx(r.time_limit(), 2.0), "2.0 s at streak 20")
	r.streak = 8
	check(is_equal_approx(r.time_limit(), 3.5), "3.5 s at streak 8")
	r.answer_wrong("stop")
	check(is_equal_approx(r.time_limit(), 4.5), "a miss resets the clock to 4.5 s")


func _scoring() -> void:
	var r := RunState.new()
	check(r.choice_count() == 3, "warm-up questions have 3 choices")
	check(r.points_for(r.time_limit()) == 200, "instant answer = base + full bonus")
	check(r.points_for(0.0) == 100, "last-moment answer = base only")
	check(r.points_for(r.time_limit() * 0.5) == 150, "half time = half bonus")
	check(r.points_for(99.0) == 200, "bonus clamped")
	check(r.multiplier() == 1, "x1 at start")
	var total := 0
	for i in 5:
		total += r.answer_correct(r.time_limit())
	check(total == 1000 and r.score == 1000, "five instant answers = 1000 (%d)" % r.score)
	check(r.multiplier() == 2, "x2 after 5 streak")
	check(r.choice_count() == 4, "4 choices after warm-up")
	check(r.answer_correct(0.0) == 200, "x2 applies to points")
	check(r.streak == 6 and r.best_streak == 6 and r.correct == 6, "streak counters")
	r.streak = 100
	check(r.multiplier() == RunState.MAX_MULT, "multiplier capped at x%d" % RunState.MAX_MULT)
	r.answer_wrong()
	check(r.streak == 0 and r.multiplier() == 1, "miss resets streak and multiplier")
	check(r.best_streak == 6, "best streak kept")


func _lives() -> void:
	var r := RunState.new()
	check(r.lives == 3 and not r.is_over(), "3 lives")
	r.answer_wrong("stop")
	r.timeout("give_way")
	r.answer_wrong("stop")
	check(r.lives == 0 and r.is_over(), "three misses end the run")
	check(Array(r.missed) == ["stop", "give_way"], "missed list deduped and ordered")
	var s := r.score
	check(r.answer_correct(4.0) == 0 and r.score == s, "no points after game over")
	r.answer_wrong()
	check(r.lives == 0, "lives never negative")
	check(r.answered == 3, "answers after game over ignored")


func _save_load() -> void:
	var dir := OS.get_environment("TMPDIR")
	if dir == "":
		dir = OS.get_user_data_dir()
	var path := dir.path_join("row-work/run_check.cfg")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	DirAccess.remove_absolute(path)
	var S = load("res://scripts/settings.gd")
	var a = S.new()
	a.path = path
	a.load_settings()
	check(a.best_score == 0 and a.runs == 0, "fresh settings")
	check(a.submit_run(1200, 7), "first score is a record")
	check(not a.submit_run(900, 9), "lower score is not a record")
	check(a.best_score == 1200 and a.best_streak == 9 and a.runs == 2, "records kept")
	a.set_language("es")
	var b = S.new()
	b.path = path
	b.load_settings()
	check(b.best_score == 1200, "best score persisted")
	check(b.best_streak == 9 and b.runs == 2, "streak + runs persisted")
	check(b.language == "es", "language persisted")
	check(b.submit_run(1201, 1), "beating it is a record")
	a.free()
	b.free()
	TranslationServer.set_locale("en")
	DirAccess.remove_absolute(path)
