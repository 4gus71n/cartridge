extends SceneTree
## Bundled content: every manifest entry is complete, its audio file exists
## and loads, licences are public domain, each playable language has enough
## clips (from more than one book or reader where possible), language notes
## exist in EN+ES, display strings fit the default font, size budget holds,
## and CREDITS.md lists every clip.

const MIN_LANGS := 15
const MAX_TOTAL_BYTES := 12 * 1024 * 1024

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _font_ok(s: String) -> bool:
	for i in s.length():
		var o := s.unicode_at(i)
		if not (o <= 0x24F or (o >= 0x370 and o <= 0x4FF) or o in [0x2019, 0x2018, 0x201C, 0x201D, 0x2013, 0x2014, 0x2026, 0xB7]):
			return false
	return true


func _initialize() -> void:
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://content/clips.json"))
	check(raw is Dictionary and raw.get("clips") is Array, "clips.json parses")
	var langs_raw = JSON.parse_string(FileAccess.get_file_as_string("res://content/languages.json"))
	check(langs_raw is Dictionary and langs_raw.get("languages") is Dictionary, "languages.json parses")
	var bank := ClipBank.load_default()
	check(bank.clips.size() == raw["clips"].size(), "every manifest clip has a known language")
	check(bank.playable.size() >= MIN_LANGS, "at least %d playable languages (%d)" % [MIN_LANGS, bank.playable.size()])
	check(bank.playable.size() == bank.by_lang.size(), "no orphan language below the minimum ships")
	var total := 0
	var ids := {}
	for c in bank.clips:
		var id: String = c["id"]
		check(not ids.has(id), "unique id " + id)
		ids[id] = true
		for k in ["file", "language", "book", "reader", "url", "license", "license_url", "audio_url",
				"book_display", "reader_display", "duration", "peaks", "source_offset_s"]:
			check(c.has(k) and str(c[k]) != "", "%s has %s" % [id, k])
		check(str(c["license"]).begins_with("Public domain"), id + " licence is public domain")
		check("publicdomain" in str(c["license_url"]).replace("-", "").to_lower(), id + " licence url is PD")
		check(str(c["url"]).begins_with("https://librivox.org/") or str(c["url"]).begins_with("http://librivox.org/"), id + " LibriVox page url")
		check("archive.org" in str(c["audio_url"]), id + " archive.org audio url")
		check(float(c["source_offset_s"]) >= 60.0, id + " cut at least 60 s in (skips intro)")
		var d := float(c["duration"])
		check(d >= 5.0 and d <= 8.0, "%s duration 5-8 s (%.2f)" % [id, d])
		check(c["peaks"] is Array and c["peaks"].size() == 64, id + " has 64 peaks")
		check(_font_ok(str(c["book_display"])) and _font_ok(str(c["reader_display"])) and _font_ok(str(c.get("author_display", ""))),
			id + " display strings fit the default font: " + str(c["book_display"]))
		var p := "res://content/" + str(c["file"])
		check(FileAccess.file_exists(p), id + " file exists " + p)
		var s := bank.stream_for(id)
		check(s is AudioStreamOggVorbis, id + " loads as Ogg Vorbis")
		if s:
			check(absf(s.get_length() - d) < 0.35, "%s stream length %.2f ~ manifest %.2f" % [id, s.get_length(), d])
		var f := FileAccess.open(p, FileAccess.READ)
		if f:
			total += f.get_length()
	check(total > 0 and total <= MAX_TOTAL_BYTES, "audio total %.2f MB within budget" % (total / 1048576.0))
	for code in bank.playable:
		var n: int = bank.by_lang[code].size()
		check(n >= ClipBank.MIN_CLIPS and n <= 10, "%s has 6-10 clips (%d)" % [code, n])
		var books := {}
		var readers := {}
		for id in bank.by_lang[code]:
			books[bank.by_id[id]["book"]] = true
			readers[bank.by_id[id]["reader"]] = true
		check(books.size() + readers.size() >= 3, "%s has variety (%d books, %d readers)" % [code, books.size(), readers.size()])
		var info: Dictionary = bank.langs[code]
		for k in ["name_en", "name_es", "family", "where_en", "where_es", "fact_en", "fact_es"]:
			check(str(info.get(k, "")) != "", "%s info has %s" % [code, k])
			check(_font_ok(str(info.get(k, ""))), "%s %s fits the default font" % [code, k])
		check(info.get("relatives") is Array, code + " relatives list")
	var credits := FileAccess.get_file_as_string("res://CREDITS.md")
	check(credits.length() > 500, "CREDITS.md present")
	for id in ids:
		check(("| %s |" % id) in credits, "CREDITS.md lists " + id)
	print("manifest_check: %d passed, %d failed (%d clips, %d languages, %.2f MB)" % [
		_pass, _fail, bank.clips.size(), bank.playable.size(), total / 1048576.0])
	quit(1 if _fail > 0 else 0)
