extends Node
## Persistent settings: language + records (best score, best chain).
## On the web, user:// lives in the WebView's IndexedDB.

const PATH := "user://settings.cfg"

var path := PATH
var language := "en"
var best_score := 0
var best_chain := 0
var games_played := 0
var _cfg := ConfigFile.new()


func _ready() -> void:
	load_from(path)
	TranslationServer.set_locale(language)


func load_from(p: String) -> void:
	path = p
	_cfg = ConfigFile.new()
	if _cfg.load(path) == OK:
		language = _cfg.get_value("general", "language", _default_language())
		best_score = int(_cfg.get_value("records", "best_score", 0))
		best_chain = int(_cfg.get_value("records", "best_chain", 0))
		games_played = int(_cfg.get_value("records", "games_played", 0))
	else:
		language = _default_language()
		best_score = 0
		best_chain = 0
		games_played = 0


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
	_cfg.set_value("general", "language", language)
	_cfg.set_value("records", "best_score", best_score)
	_cfg.set_value("records", "best_chain", best_chain)
	_cfg.set_value("records", "games_played", games_played)
	_cfg.save(path)
