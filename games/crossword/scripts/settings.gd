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
## "<lang>/<tier>" -> best clean solve time in that tier, in seconds.
var tier_best := {}
var _cfg := ConfigFile.new()


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	_cfg = ConfigFile.new()
	best = {}
	progress = {}
	last = {}
	tier_best = {}
	if CartridgeStore.load_cfg(_cfg, path) == OK:
		# Every field is validated: a save written by an older build, or a
		# corrupted one, must load as empty rather than crash the game.
		var lang: Variant = _cfg.get_value("general", "language", "")
		language = str(lang) if lang is String and lang != "" else _default_language()
		best = _dict(_cfg.get_value("records", "best", {}))
		progress = _dict(_cfg.get_value("records", "progress", {}))
		last = _dict(_cfg.get_value("records", "last", {}))
		tier_best = _dict(_cfg.get_value("records", "tier_best", {}))
	else:
		language = _default_language()
	TranslationServer.set_locale(language)


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


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


## Best clean time for a whole tier, or -1 when none yet.
func tier_best_time(lang: String, tier: String) -> float:
	return float(tier_best.get("%s/%s" % [lang, tier], -1))


## Stores a finished puzzle. Returns true when it is a new best clean time.
## `lang`/`tier` are optional: when given, the tier record is kept too.
func record_solve(id: String, seconds: float, assisted: bool,
		lang := "", tier := "") -> bool:
	progress.erase(id)
	var old := float(best.get(id, -1))
	var record := false
	if assisted:
		if not best.has(id):
			best[id] = -1
	elif old < 0 or seconds < old:
		best[id] = snappedf(seconds, 0.1)
		record = true
	if not assisted and lang != "" and tier != "":
		var key := "%s/%s" % [lang, tier]
		var prev := float(tier_best.get(key, -1))
		if prev < 0 or seconds < prev:
			tier_best[key] = snappedf(seconds, 0.1)
	save()
	return record


## Forgets in-progress boards and "last played" ids this build no longer has
## (the pack was rebuilt). Best times are tiny and harmless, so they stay.
func drop_unknown(known_ids: Dictionary) -> void:
	for id in progress.keys():
		if not known_ids.has(id):
			progress.erase(id)
	for lang in last.keys():
		if not known_ids.has(last[lang]):
			last.erase(lang)
	save()


func save_progress(id: String, state: Dictionary) -> void:
	progress[id] = state
	last[language] = id
	save()


func save() -> void:
	_cfg.set_value("general", "language", language)
	_cfg.set_value("records", "best", best)
	_cfg.set_value("records", "progress", progress)
	_cfg.set_value("records", "last", last)
	_cfg.set_value("records", "tier_best", tier_best)
	CartridgeStore.save_cfg(_cfg, path)
