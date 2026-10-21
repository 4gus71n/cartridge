extends SceneTree
## Corrupt-save probe: unparseable settings / run files must fall back to
## defaults without crashing. The engine prints ConfigFile parse ERRORs here
## by design, so tools/run_tests.sh runs this file separately and only fails
## on a non-zero exit or a SCRIPT ERROR.
##   godot --headless --path . --script tests/corrupt_probe.gd

const SettingsScript := preload("res://scripts/settings.gd")
const TEST_PATH := "user://corrupt_probe_settings.cfg"
const RUN_PATH := "user://corrupt_probe_run.cfg"

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _write(p: String, text: String) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _initialize() -> void:
	_write(TEST_PATH, "[general\nlanguage=\"es")
	var s = SettingsScript.new()
	s.load_from(TEST_PATH)
	check(s.best_score == 0 and (s.language == "en" or s.language == "es"), "corrupt settings fall back to defaults")
	s.submit_game(10, 1)
	s.free()
	var t = SettingsScript.new()
	t.load_from(TEST_PATH)
	check(t.best_score == 10, "a corrupt settings file is replaced by a good one on save")
	t.free()

	RunSave.path = RUN_PATH
	_write(RUN_PATH, "garbage ===\n[[[")
	check(RunSave.load_run() == null, "corrupt run file discarded")
	_write(RUN_PATH, "")
	check(RunSave.load_run() == null, "empty run file discarded")
	RunSave.clear()
	RunSave.path = RunSave.PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	print("corrupt_probe: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
