extends Node
## Persistent settings: language + records. Saved via CartridgeStore (app
## storage bridge; user:// fallback).
##
## Records for the current rules ("stone rise", v2) live in [records_v2].
## Records set under the old, much easier v1 rules stay in [records] untouched
## and are only shown as a labelled "classic" line, so they never mask v2 bests.

const PATH := "user://settings.cfg"

var path := PATH
var language := "en"
var best_score := 0 # v2
var best_chain := 0 # v2
var games_played := 0 # v2
var legacy_best_score := 0 # v1 rules, read-only
var legacy_best_chain := 0
var _cfg := ConfigFile.new()


func _ready() -> void:
	load_from(path)
	TranslationServer.set_locale(language)


func load_from(p: String) -> void:
	path = p
	_cfg = ConfigFile.new()
	if CartridgeStore.load_cfg(_cfg, path) == OK:
		language = str(_cfg.get_value("general", "language", _default_language()))
		if language != "en" and language != "es":
			language = _default_language()
		best_score = int(_cfg.get_value("records_v2", "best_score", 0))
		best_chain = int(_cfg.get_value("records_v2", "best_chain", 0))
		games_played = int(_cfg.get_value("records_v2", "games_played", 0))
		legacy_best_score = int(_cfg.get_value("records", "best_score", 0))
		legacy_best_chain = int(_cfg.get_value("records", "best_chain", 0))
	else:
		_cfg = ConfigFile.new()
		language = _default_language()
		best_score = 0
		best_chain = 0
		games_played = 0
		legacy_best_score = 0
		legacy_best_chain = 0


func _default_language() -> String:
	return "es" if OS.get_locale_language() == "es" else "en"


func set_language(lang: String) -> void:
	language = lang
	TranslationServer.set_locale(lang)
	save()


## Records a finished game. Returns true when `score` is a new best score.
func submit_game(score: int, chain: int) -> bool:
	games_played += 1
	best_chain = maxi(best_chain, chain)
	var record := score > best_score
	if record:
		best_score = score
	save()
	return record


func save() -> void:
	# [records] (v1) is left exactly as loaded.
	_cfg.set_value("general", "language", language)
	_cfg.set_value("records_v2", "best_score", best_score)
	_cfg.set_value("records_v2", "best_chain", best_chain)
	_cfg.set_value("records_v2", "games_played", games_played)
	CartridgeStore.save_cfg(_cfg, path)
