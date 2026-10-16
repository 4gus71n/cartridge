extends SceneTree
## Persistence: godot --headless --path . --script tests/save_check.gd
## Uses its own cfg file in user:// so real records are untouched.

const SettingsScript := preload("res://scripts/settings.gd")
const TEST_PATH := "user://save_check_test.cfg"

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
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
	check(t.best_score == 501, "best score persisted (%d)" % t.best_score)
	check(t.best_chain == 4, "best chain persisted")
	check(t.games_played == 3, "games played persisted")
	check(t.language == "es", "language persisted")
	t.free()

	# A real game: board score feeds the record.
	var b := PrismBoard.new(9, 16, 3)
	b.start()
	while b.state != PrismBoard.State.OVER:
		b.hard_drop()
		if b.state == PrismBoard.State.RESOLVING:
			b.resolve_all()
	var u = SettingsScript.new()
	u.load_from(TEST_PATH)
	var rec: bool = u.submit_game(b.score + 10000, b.best_chain)
	check(rec, "game score above best is saved as record")
	u.free()
	var v = SettingsScript.new()
	v.load_from(TEST_PATH)
	check(v.best_score == b.score + 10000, "record from a played game persisted")
	v.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	print("save_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
