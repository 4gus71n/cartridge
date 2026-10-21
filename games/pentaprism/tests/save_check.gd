extends SceneTree
## Persistence: godot --headless --path . --script tests/save_check.gd
## Uses its own files in user:// so real records/runs are untouched.
## Unparseable files are covered by tests/corrupt_probe.gd (the engine logs
## parse ERRORs there on purpose, which this gate would otherwise flag).

const SettingsScript := preload("res://scripts/settings.gd")
const Bot := preload("res://tests/prism_bot.gd")
const TEST_PATH := "user://save_check_test.cfg"
const RUN_PATH := "user://save_check_run.cfg"

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _rm(p: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _initialize() -> void:
	_records()
	_v1_settings()
	_run_round_trip()
	_run_rejects_bad_saves()
	_rm(TEST_PATH)
	_rm(RUN_PATH)
	print("save_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _records() -> void:
	_rm(TEST_PATH)
	var s = SettingsScript.new()
	s.load_from(TEST_PATH)
	check(s.best_score == 0 and s.best_chain == 0, "fresh records are zero")
	check(s.submit_game(500, 2), "first score is a record")
	check(not s.submit_game(300, 4), "lower score is not a record")
	check(s.best_chain == 4, "best chain tracked independently")
	check(s.submit_game(501, 1), "higher score is a record")
	s.language = "es"
	s.save()
	s.free()
	var t = SettingsScript.new()
	t.load_from(TEST_PATH)
	check(t.best_score == 501 and t.best_chain == 4 and t.games_played == 3, "v2 records persisted")
	check(t.language == "es", "language persisted")
	t.free()
	var cfg := ConfigFile.new()
	cfg.load(TEST_PATH)
	check(cfg.has_section_key("records_v2", "best_score"), "v2 records stored under [records_v2]")
	check(not cfg.has_section_key("records", "best_score"), "no v1 keys invented")


func _v1_settings() -> void:
	# A settings file exactly as v1 wrote it.
	_rm(TEST_PATH)
	var old := ConfigFile.new()
	old.set_value("general", "language", "es")
	old.set_value("records", "best_score", 24860)
	old.set_value("records", "best_chain", 6)
	old.set_value("records", "games_played", 12)
	old.save(TEST_PATH)
	var s = SettingsScript.new()
	s.load_from(TEST_PATH)
	check(s.language == "es", "v1 language still loads")
	check(s.legacy_best_score == 24860 and s.legacy_best_chain == 6, "v1 records kept as legacy")
	check(s.best_score == 0 and s.best_chain == 0, "v1 easy scores don't become v2 records")
	check(s.submit_game(1200, 2), "first v2 game is a v2 record despite a bigger v1 score")
	s.free()
	var t = SettingsScript.new()
	t.load_from(TEST_PATH)
	check(t.best_score == 1200 and t.legacy_best_score == 24860, "v1 legacy untouched after a v2 save")
	t.free()


func _play(b: PrismBoard, n: int) -> void:
	for i in n:
		if b.state != PrismBoard.State.PLAYING:
			return
		var best := Bot.best_placement(b)
		if not best.is_empty():
			b.current.cells = best.cells
			b.current.pos.x = best.x
		b.hard_drop()
		if b.state == PrismBoard.State.RESOLVING:
			b.resolve_all()


func _run_round_trip() -> void:
	_rm(RUN_PATH)
	RunSave.path = RUN_PATH
	check(not RunSave.exists() and RunSave.load_run() == null, "no run saved yet")
	var a := PrismBoard.new(9, 16, Bot.seed_for(3))
	a.start()
	_play(a, 23)
	a.hold()
	check(a.state == PrismBoard.State.PLAYING and a.pieces_placed == 23, "bot run in progress")
	RunSave.save(a)
	check(RunSave.exists(), "run saved")
	var b := RunSave.load_run()
	check(b != null, "run loads back")
	if b == null:
		return
	check(b.grid == a.grid, "grid restored (stones included)")
	check(b.score == a.score and b.level == a.level and b.pieces_placed == a.pieces_placed, "score/level/pieces restored")
	check(b.stones_in == a.stones_in and b.next_gaps == a.next_gaps, "stone countdown + next gaps restored")
	check(b.combo == a.combo and b.best_chain == a.best_chain and b.cleared_cells == a.cleared_cells, "combo/chain/cleared restored")
	check(b.current.shape == a.current.shape and b.current.colors == a.current.colors, "current piece restored")
	check(b.held != null and b.held.shape == a.held.shape and b.can_hold == a.can_hold, "hold slot restored")
	var qa := []
	var qb := []
	for p in a.queue:
		qa.append([p.shape, p.colors])
	for p in b.queue:
		qb.append([p.shape, p.colors])
	check(qa == qb, "next queue restored")
	# Both runs continue identically (bag + crack/gap rng restored).
	_play(a, 40)
	_play(b, 40)
	check(a.grid == b.grid and a.score == b.score and a.state == b.state, "resumed run continues identically (score %d)" % a.score)
	RunSave.clear()
	check(not RunSave.exists() and RunSave.load_run() == null, "cleared run is gone")


func _run_rejects_bad_saves() -> void:
	RunSave.path = RUN_PATH
	var cfg := ConfigFile.new()
	cfg.set_value("run", "version", 1)
	cfg.set_value("run", "data", {"v": 1})
	cfg.save(RUN_PATH)
	check(RunSave.load_run() == null, "other-version run discarded")
	cfg.set_value("run", "version", 2)
	cfg.set_value("run", "data", {"v": 2, "w": 9, "h": 16, "grid": [1, 2]})
	cfg.save(RUN_PATH)
	check(RunSave.load_run() == null, "wrong-size grid discarded")
	# A run whose spawn would be blocked is not offered.
	var b := PrismBoard.new(9, 16, 5)
	b.start()
	var d := b.to_dict()
	var g: Array = d.grid
	for i in 27:
		g[i] = 3
	cfg = ConfigFile.new()
	cfg.set_value("run", "version", 2)
	cfg.set_value("run", "data", d)
	cfg.save(RUN_PATH)
	check(RunSave.load_run() == null, "already-lost run not offered")
	RunSave.save(null)
	RunSave.clear()
	RunSave.path = RunSave.PATH
