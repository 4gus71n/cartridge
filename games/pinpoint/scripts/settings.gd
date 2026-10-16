extends Node
## Persistent settings + records: language, distance units, best score,
## recently seen photos and the in-progress game (resume).
## On the web, user:// lives in the WebView's IndexedDB.

const PATH := "user://settings.cfg"
const RECENT_MAX := 90

var language := "en"
var miles := false
var best_score := 0
var games_played := 0
var recent: Array = []          # photo ids, oldest first
var saved_game: Dictionary = {} # PinpointGame.to_dict() or {}
var path := PATH
var _cfg := ConfigFile.new()


func _ready() -> void:
	load_from(path)


func load_from(p: String) -> void:
	path = p
	_cfg = ConfigFile.new()
	if _cfg.load(path) == OK:
		language = _cfg.get_value("general", "language", _default_language())
		miles = _cfg.get_value("general", "miles", GeoMath.locale_uses_miles(OS.get_locale()))
		best_score = _cfg.get_value("records", "best_score", 0)
		games_played = _cfg.get_value("records", "games_played", 0)
		recent = _cfg.get_value("records", "recent", [])
		saved_game = _cfg.get_value("game", "saved", {})
	else:
		language = _default_language()
		miles = GeoMath.locale_uses_miles(OS.get_locale())
	TranslationServer.set_locale(language)


func _default_language() -> String:
	return "es" if OS.get_locale_language() == "es" else "en"


func set_language(lang: String) -> void:
	language = lang
	TranslationServer.set_locale(lang)
	save()


func toggle_units() -> void:
	miles = not miles
	save()


## Returns true when `score` is a new best.
func submit_score(score: int) -> bool:
	games_played += 1
	var record := score > best_score
	if record:
		best_score = score
	save()
	return record


func mark_seen(ids: Array) -> void:
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
	_cfg.set_value("general", "miles", miles)
	_cfg.set_value("records", "best_score", best_score)
	_cfg.set_value("records", "games_played", games_played)
	_cfg.set_value("records", "recent", recent)
	_cfg.set_value("game", "saved", saved_game)
	_cfg.save(path)
