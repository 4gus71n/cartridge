extends Node
## Persistent settings: language + best score / streak.
## Saved via CartridgeStore (app storage bridge; user:// fallback).

const PATH := "user://settings.cfg"

var path := PATH
var language := "en"
var best_score := 0
var best_streak := 0
var runs := 0
var _cfg := ConfigFile.new()


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	_cfg = ConfigFile.new()
	if CartridgeStore.load_cfg(_cfg, path) == OK:
		language = _cfg.get_value("general", "language", _default_language())
		best_score = int(_cfg.get_value("records", "best_score", 0))
		best_streak = int(_cfg.get_value("records", "best_streak", 0))
		runs = int(_cfg.get_value("records", "runs", 0))
	else:
		language = _default_language()
	TranslationServer.set_locale(language)


func _default_language() -> String:
	return "es" if OS.get_locale_language() == "es" else "en"


func set_language(lang: String) -> void:
	language = lang
	TranslationServer.set_locale(lang)
	save()


## Records a finished run. Returns true when `score` is a new best.
func submit_run(score: int, streak: int) -> bool:
	runs += 1
	best_streak = maxi(best_streak, streak)
	var record := score > best_score
	if record:
		best_score = score
	save()
	return record


func save() -> void:
	_cfg.set_value("general", "language", language)
	_cfg.set_value("records", "best_score", best_score)
	_cfg.set_value("records", "best_streak", best_streak)
	_cfg.set_value("records", "runs", runs)
	CartridgeStore.save_cfg(_cfg, path)
