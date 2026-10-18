class_name ClipBank
extends RefCounted
## The bundled clip manifest (content/clips.json) plus language notes
## (content/languages.json). Only languages with at least MIN_CLIPS clips are
## playable. Pure data: no scene dependency, so tests can build tiny banks.

const CLIPS_PATH := "res://content/clips.json"
const LANGS_PATH := "res://content/languages.json"
const MIN_CLIPS := 3

var clips: Array = []            # manifest entries (Dictionary)
var by_id := {}                  # id -> entry
var by_lang := {}                # code -> Array[String] of clip ids
var langs := {}                  # code -> info dict from languages.json
var playable: Array[String] = [] # sorted language codes with >= min clips


static func load_default() -> ClipBank:
	var clips_json: Dictionary = _read_json(CLIPS_PATH)
	var langs_json: Dictionary = _read_json(LANGS_PATH)
	return from_data(clips_json.get("clips", []), langs_json.get("languages", {}), MIN_CLIPS)


static func from_data(clip_list: Array, lang_info: Dictionary, min_clips := MIN_CLIPS) -> ClipBank:
	var b := ClipBank.new()
	b.langs = lang_info
	for c in clip_list:
		if not (c is Dictionary) or not c.has("id") or not c.has("language"):
			continue
		if not lang_info.has(c["language"]):
			continue
		b.clips.append(c)
		b.by_id[c["id"]] = c
		if not b.by_lang.has(c["language"]):
			b.by_lang[c["language"]] = []
		b.by_lang[c["language"]].append(c["id"])
	for code in b.by_lang:
		if b.by_lang[code].size() >= min_clips:
			b.playable.append(code)
	b.playable.sort()
	return b


static func _read_json(p: String) -> Dictionary:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		push_error("ClipBank: cannot open " + p)
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func _es() -> bool:
	return TranslationServer.get_locale().begins_with("es")


func name_of(code: String) -> String:
	var info: Dictionary = langs.get(code, {})
	return str(info.get("name_es" if _es() else "name_en", code))


func where_of(code: String) -> String:
	var info: Dictionary = langs.get(code, {})
	return str(info.get("where_es" if _es() else "where_en", ""))


func fact_of(code: String) -> String:
	var info: Dictionary = langs.get(code, {})
	return str(info.get("fact_es" if _es() else "fact_en", ""))


func family_of(code: String) -> String:
	return str(langs.get(code, {}).get("family", code))


## Close relatives that are playable: explicit list first, then same family.
func relatives_of(code: String) -> Array[String]:
	var out: Array[String] = []
	for r in langs.get(code, {}).get("relatives", []):
		if r != code and r in playable and not (r in out):
			out.append(r)
	for other in playable:
		if other != code and family_of(other) == family_of(code) and not (other in out):
			out.append(other)
	return out


func voices() -> int:
	var seen := {}
	for c in clips:
		if c["language"] in playable:
			seen[str(c.get("reader", ""))] = true
	return seen.size()


func stream_for(id: String) -> AudioStream:
	var c: Dictionary = by_id.get(id, {})
	if c.is_empty():
		return null
	var p := "res://content/" + str(c["file"])
	return load(p) as AudioStream if ResourceLoader.exists(p) else null
