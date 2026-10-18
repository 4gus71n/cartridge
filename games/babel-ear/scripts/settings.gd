extends Node
## Persistent settings + records: UI language, best score per mode, games
## played, recently heard clips (avoid repeats across games) and the
## in-progress game (resume). On the web, user:// lives in IndexedDB.

const PATH := "user://settings.cfg"
const RECENT_MAX := 60

var language := "en"
var best := {"easy": 0, "hard": 0}
var games_played := 0
var recent: Array = []           # clip ids, oldest first
var saved_game: Dictionary = {}  # BabelGame.to_dict() or {}
var path := PATH
var _cfg := ConfigFile.new()


func _ready() -> void:
	load_from(path)


func load_from(p: String) -> void:
	path = p
	_cfg = ConfigFile.new()
	best = {"easy": 0, "hard": 0}
	games_played = 0
	recent = []
	saved_game = {}
	if _cfg.load(path) == OK:
		language = str(_cfg.get_value("general", "language", _default_language()))
		if language != "en" and language != "es":
			language = "en"
		for m in ["easy", "hard"]:
			best[m] = maxi(0, int(_cfg.get_value("records", "best_" + m, 0)))
		games_played = int(_cfg.get_value("records", "games_played", 0))
		var r = _cfg.get_value("records", "recent", [])
		recent = r if r is Array else []
		var g = _cfg.get_value("game", "saved", {})
		saved_game = g if g is Dictionary else {}
	else:
		language = _default_language()
	TranslationServer.set_locale(language)


func _default_language() -> String:
	return "es" if OS.get_locale_language() == "es" else "en"


func set_language(lang: String) -> void:
	language = lang
	TranslationServer.set_locale(lang)
	save()


func best_for(mode_key: String) -> int:
	return int(best.get(mode_key, 0))


## Returns true when `score` is a new best for that mode.
func submit_score(mode_key: String, score: int) -> bool:
	games_played += 1
	var record := score > best_for(mode_key)
	if record:
		best[mode_key] = score
	saved_game = {}
	save()
	return record


func mark_heard(ids: Array) -> void:
	for id in ids:
		recent.erase(id)
		recent.append(id)
	while recent.size() > RECENT_MAX:
		recent.pop_front()
	save()


func save_game(d: Dictionary) -> void:
	saved_game = d
	save()


func save() -> void:
	_cfg.set_value("general", "language", language)
	_cfg.set_value("records", "best_easy", best_for("easy"))
	_cfg.set_value("records", "best_hard", best_for("hard"))
	_cfg.set_value("records", "games_played", games_played)
	_cfg.set_value("records", "recent", recent)
	_cfg.set_value("game", "saved", saved_game)
	_cfg.save(path)
