extends Node
## Persistent settings + local high scores (user://settings.cfg) and the
## autosaved run in progress (a separate file, rewritten every turn).
## On the web, user:// lives in the WebView's IndexedDB.

const PATH := "user://settings.cfg"
const MAX_SCORES := 10

var path := PATH
var language := "en"
var scores: Array = [] ## {score, depth, turns, lvl, won, cause, code}
var runs := 0
var wins := 0
var _cfg := ConfigFile.new()
var _run_cache := {}


func _ready() -> void:
	load_from(path)
	TranslationServer.set_locale(language)


func run_path() -> String:
	return path.get_basename() + "_run.cfg"


func load_from(p: String) -> void:
	path = p
	_cfg = ConfigFile.new()
	var ok := _cfg.load(path) == OK
	language = _cfg.get_value("general", "language", _default_language()) if ok else _default_language()
	var s: Variant = _cfg.get_value("records", "scores", [])
	scores = s if s is Array else []
	runs = int(_cfg.get_value("records", "runs", 0))
	wins = int(_cfg.get_value("records", "wins", 0))
	var rc := ConfigFile.new()
	_run_cache = {}
	if rc.load(run_path()) == OK:
		var d: Variant = rc.get_value("run", "state", {})
		if d is Dictionary and d.get("state", "") == "play":
			_run_cache = d


func _default_language() -> String:
	return "es" if OS.get_locale_language() == "es" else "en"


func set_language(lang: String) -> void:
	language = lang
	TranslationServer.set_locale(lang)
	save()


func has_run() -> bool:
	return not _run_cache.is_empty()


func saved_run() -> Dictionary:
	return _run_cache


func store_run(d: Dictionary) -> void:
	_run_cache = d
	var rc := ConfigFile.new()
	rc.set_value("run", "state", d)
	rc.save(run_path())


func clear_run() -> void:
	_run_cache = {}
	if FileAccess.file_exists(run_path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(run_path()))


## Records a finished run; returns its rank (0-based) or -1 if off the table.
func add_score(e: Dictionary) -> int:
	runs += 1
	if e.get("won", false):
		wins += 1
	scores.append(e)
	scores.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.score) > int(b.score))
	var rank := -1
	for i in scores.size():
		if is_same(scores[i], e):
			rank = i
	if scores.size() > MAX_SCORES:
		scores = scores.slice(0, MAX_SCORES)
	if rank >= MAX_SCORES:
		rank = -1
	save()
	return rank


func best_score() -> int:
	return int(scores[0].score) if not scores.is_empty() else 0


func save() -> void:
	_cfg.set_value("general", "language", language)
	_cfg.set_value("records", "scores", scores)
	_cfg.set_value("records", "runs", runs)
	_cfg.set_value("records", "wins", wins)
	_cfg.save(path)
