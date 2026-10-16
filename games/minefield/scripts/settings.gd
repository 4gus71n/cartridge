extends Node
## Persistent settings: language + best times per difficulty.
## On the web, user:// lives in the WebView's IndexedDB.

const PATH := "user://settings.cfg"

var language := "en"
var best_times := {} # difficulty id -> seconds (float)
var _cfg := ConfigFile.new()


func _ready() -> void:
	if _cfg.load(PATH) == OK:
		language = _cfg.get_value("general", "language", _default_language())
		best_times = _cfg.get_value("records", "best_times", {})
	else:
		language = _default_language()
	TranslationServer.set_locale(language)


func _default_language() -> String:
	return "es" if OS.get_locale_language() == "es" else "en"


func set_language(lang: String) -> void:
	language = lang
	TranslationServer.set_locale(lang)
	save()


## Returns true when `seconds` is a new record.
func submit_time(difficulty: String, seconds: float) -> bool:
	var prev: float = best_times.get(difficulty, INF)
	if seconds < prev:
		best_times[difficulty] = seconds
		save()
		return true
	return false


func save() -> void:
	_cfg.set_value("general", "language", language)
	_cfg.set_value("records", "best_times", best_times)
	_cfg.save(PATH)


static func format_time(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]
