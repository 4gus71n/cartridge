extends Node
## Persistent settings + records + the saved in-progress game.
## Saved via CartridgeStore (app storage bridge; user:// fallback).

const PATH := "user://settings.cfg"

var path := PATH
var language := "en"
var mistake_check := true
var best_times := {1: 0.0, 2: 0.0, 3: 0.0} ## seconds, 0 = none yet
var solved := {1: 0, 2: 0, 3: 0}
var streak := 0 ## consecutive daily puzzles solved
var best_streak := 0
var last_daily := -1 ## day number of the last solved daily
var saved_game := {} ## SudokuGame.to_dict() of the game in progress, {} = none
var _cfg := ConfigFile.new()


func _ready() -> void:
	load_from(path)
	TranslationServer.set_locale(language)


func load_from(p: String) -> void:
	path = p
	_cfg = ConfigFile.new()
	var ok := CartridgeStore.load_cfg(_cfg, path) == OK
	language = _cfg.get_value("general", "language", _default_language()) if ok else _default_language()
	mistake_check = bool(_cfg.get_value("general", "mistake_check", true))
	for lv in [1, 2, 3]:
		best_times[lv] = float(_cfg.get_value("records", "best_%d" % lv, 0.0))
		solved[lv] = int(_cfg.get_value("records", "solved_%d" % lv, 0))
	streak = int(_cfg.get_value("daily", "streak", 0))
	best_streak = int(_cfg.get_value("daily", "best_streak", 0))
	last_daily = int(_cfg.get_value("daily", "last", -1))
	var raw: String = _cfg.get_value("game", "state", "")
	var parsed = JSON.parse_string(raw) if raw != "" else null
	saved_game = parsed if parsed is Dictionary else {}


func _default_language() -> String:
	return "es" if OS.get_locale_language() == "es" else "en"


func set_language(lang: String) -> void:
	language = lang
	TranslationServer.set_locale(lang)
	save()


func set_mistake_check(on: bool) -> void:
	mistake_check = on
	save()


## Streak as it stands today: broken if yesterday's daily was missed.
func current_streak(today: int) -> int:
	return streak if last_daily >= today - 1 else 0


func daily_done(today: int) -> bool:
	return last_daily == today


## Records a solved puzzle. Returns true for a new best time on that level.
func record_win(level: int, seconds: float, daily_day := -1) -> bool:
	solved[level] = int(solved.get(level, 0)) + 1
	var prev: float = best_times.get(level, 0.0)
	var record := prev <= 0.0 or seconds < prev
	if record:
		best_times[level] = seconds
	if daily_day >= 0 and daily_day > last_daily:
		streak = streak + 1 if last_daily == daily_day - 1 else 1
		last_daily = daily_day
		best_streak = maxi(best_streak, streak)
	saved_game = {}
	save()
	return record


func store_game(d: Dictionary) -> void:
	saved_game = d
	save()


func clear_game() -> void:
	saved_game = {}
	save()


func save() -> void:
	_cfg.set_value("general", "language", language)
	_cfg.set_value("general", "mistake_check", mistake_check)
	for lv in [1, 2, 3]:
		_cfg.set_value("records", "best_%d" % lv, best_times[lv])
		_cfg.set_value("records", "solved_%d" % lv, solved[lv])
	_cfg.set_value("daily", "streak", streak)
	_cfg.set_value("daily", "best_streak", best_streak)
	_cfg.set_value("daily", "last", last_daily)
	_cfg.set_value("game", "state", JSON.stringify(saved_game) if not saved_game.is_empty() else "")
	CartridgeStore.save_cfg(_cfg, path)
