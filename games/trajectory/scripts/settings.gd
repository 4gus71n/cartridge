extends Node
## Autoload: language + persisted level progress (user:// = IndexedDB on web).

const PATH := "user://trajectory.cfg"

var progress := Progress.new()
var language := "en"


func _ready() -> void:
	progress.load_from(PATH)
	language = progress.language if progress.language in ["en", "es"] else _default_language()
	TranslationServer.set_locale(language)


func _default_language() -> String:
	return "es" if OS.get_locale_language() == "es" else "en"


func set_language(lang: String) -> void:
	language = lang
	TranslationServer.set_locale(lang)
	save()


func save() -> void:
	progress.language = language
	progress.save_to(PATH)
