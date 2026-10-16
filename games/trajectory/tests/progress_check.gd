extends SceneTree
## Stars + save/load suite.

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	_star_logic()
	_unlocking()
	_save_load()
	print("progress_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _star_logic() -> void:
	check(Progress.stars_for_attempts(1) == 3, "first try = 3 stars")
	check(Progress.stars_for_attempts(2) == 2, "2 tries = 2 stars")
	check(Progress.stars_for_attempts(3) == 2, "3 tries = 2 stars")
	check(Progress.stars_for_attempts(4) == 1, "4 tries = 1 star")
	check(Progress.stars_for_attempts(50) == 1, "many tries still 1 star")
	var p := Progress.new()
	check(p.record(0, 2), "first record improves")
	check(not p.record(0, 1), "worse result does not overwrite")
	check(p.best(0) == 2, "best kept")
	check(p.record(0, 3), "better result improves")
	check(p.best(0) == 3 and p.total_stars() == 3, "best 3 / total 3")


func _unlocking() -> void:
	var p := Progress.new()
	check(p.unlocked(0), "level 0 always unlocked")
	check(not p.unlocked(1), "level 1 locked at start")
	check(p.next_level(30) == 0, "next level is 0 at start")
	p.record(0, 1)
	check(p.unlocked(1) and not p.unlocked(2), "solving 0 unlocks 1 only")
	check(p.next_level(30) == 1, "next level advances")
	for i in 30:
		p.record(i, 3)
	check(p.next_level(30) == 29, "all solved -> last level")
	check(p.total_stars() == 90, "90 stars max")


func _save_load() -> void:
	var dir := OS.get_environment("TMPDIR")
	if dir == "":
		dir = "user://"
	var path := dir.path_join("trajectory-work/progress_test.cfg")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var p := Progress.new()
	p.record(0, 3)
	p.record(1, 2)
	p.record(7, 1)
	p.seen["CONST"] = true
	p.language = "es"
	p.last_level = 7
	p.set_draft(4, "2x+1", 3)
	p.set_draft(5, "{\"m\":0.5}", 1)
	check(p.save_to(path) == OK, "save ok")
	var q := Progress.new()
	check(q.load_from(path), "load ok")
	check(q.best(0) == 3 and q.best(1) == 2 and q.best(7) == 1 and q.best(2) == 0, "stars round-trip")
	check(q.seen.has("CONST") and q.seen.size() == 1, "seen round-trip")
	check(q.language == "es", "language round-trip")
	check(q.last_level == 7, "last level round-trip")
	check(q.draft(4) == {"input": "2x+1", "tries": 3} and q.draft(5).input == "{\"m\":0.5}", "drafts round-trip")
	check(q.draft(6).is_empty(), "no draft -> empty")
	check(q.total_stars() == 6, "total after load")
	q.record(4, 2)
	check(q.draft(4).is_empty(), "solving a level clears its draft")
	check(not Progress.new().load_from(path + ".missing"), "missing file -> false")
	# Corrupt values are ignored, not crashing.
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "stars", {"0": 9, "x": 2, "3": 2})
	cfg.set_value("progress", "seen", "garbage")
	cfg.set_value("progress", "drafts", {"1": "bad", "z": {}, "2": {"input": 5, "tries": -4}})
	cfg.save(path)
	var r := Progress.new()
	check(r.load_from(path), "load corrupt file")
	check(r.best(0) == 0 and r.best(3) == 2 and r.stars.size() == 1, "invalid star entries dropped")
	check(r.drafts.size() == 1 and r.draft(2) == {"input": "5", "tries": 0}, "invalid drafts dropped/sanitised")
	DirAccess.remove_absolute(path)
