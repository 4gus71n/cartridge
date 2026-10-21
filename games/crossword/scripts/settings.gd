extends Node
## Persistent settings + records: language, best time per puzzle, and the
## in-progress board of every started puzzle (resume). saved via CartridgeStore (app storage bridge)
## on the web.

const PATH := "user://settings.cfg"

var path := PATH
var language := "en"
## puzzle id -> best solve time in seconds (-1 = solved with reveals).
var best := {}
## puzzle id -> Board.to_dict() of an unfinished puzzle.
var progress := {}
## language -> id of the last puzzle opened.
var last := {}
var _cfg := ConfigFile.new()


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	_cfg = ConfigFile.new()
	best = {}
	progress = {}
	last = {}
	if CartridgeStore.load_cfg(_cfg, path) == OK:
		language = _cfg.get_value("general", "language", _default_language())
		best = _cfg.get_value("records", "best", {})
		progress = _cfg.get_value("records", "progress", {})
		last = _cfg.get_value("records", "last", {})
	else:
		language = _default_language()
	TranslationServer.set_locale(language)


func _default_language() -> String:
	return "es" if OS.get_locale_language() == "es" else "en"


func set_language(lang: String) -> void:
	language = lang
	TranslationServer.set_locale(lang)
	save()


func is_solved(id: String) -> bool:
	return best.has(id)


## Best clean time in seconds, or -1 when only solved with help / never.
func best_time(id: String) -> float:
	return float(best.get(id, -1))


## Stores a finished puzzle. Returns true when it is a new best clean time.
func record_solve(id: String, seconds: float, assisted: bool) -> bool:
	progress.erase(id)
	var old := float(best.get(id, -1))
	var record := false
	if assisted:
		if not best.has(id):
			best[id] = -1
	elif old < 0 or seconds < old:
		best[id] = snappedf(seconds, 0.1)
		record = true
	save()
	return record


func save_progress(id: String, state: Dictionary) -> void:
	progress[id] = state
	last[language] = id
	save()


func save() -> void:
	_cfg.set_value("general", "language", language)
	_cfg.set_value("records", "best", best)
	_cfg.set_value("records", "progress", progress)
	_cfg.set_value("records", "last", last)
	CartridgeStore.save_cfg(_cfg, path)
