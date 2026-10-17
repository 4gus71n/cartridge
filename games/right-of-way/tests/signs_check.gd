extends SceneTree
## Sign data integrity: every sign has a draw routine, a valid category, a
## distractor pool of real signs, and non-empty EN + ES name / action /
## explanation. Actions must be unique per language (a question can never
## show two identical buttons). Every tr("KEY") used by the UI must exist.

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	var rows := _load_csv()
	_catalog()
	_texts(rows)
	_ui_keys(rows)
	print("signs_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _load_csv() -> Dictionary:
	var f := FileAccess.open("res://i18n/strings.csv", FileAccess.READ)
	check(f != null, "strings.csv readable")
	var rows := {}
	var header := f.get_csv_line()
	check(header == PackedStringArray(["keys", "en", "es"]), "csv header keys,en,es")
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() == 1 and line[0] == "":
			continue
		check(line.size() == 3, "csv row has 3 columns: %s" % [line])
		if line.size() >= 3:
			check(not rows.has(line[0]), "duplicate key " + line[0])
			rows[line[0]] = {"en": line[1], "es": line[2]}
	return rows


func _catalog() -> void:
	var ids := SignCatalog.ids()
	check(ids.size() >= 40, "at least 40 signs (%d)" % ids.size())
	var seen := {}
	for s in SignCatalog.SIGNS:
		var id: String = s.id
		check(not seen.has(id), "unique id " + id)
		seen[id] = true
		check(SignCatalog.CATEGORIES.has(s.cat), "%s has a valid category" % id)
		check(SignPainter.has_routine(id), "%s has a draw routine" % id)
		check(SignCatalog.get_sign(id).id == id, "lookup " + id)
		var pool: Array = s.pool
		check(pool.size() >= 3, "%s pool has >= 3 distractors" % id)
		var pool_seen := {}
		for p in pool:
			check(SignCatalog.has_sign(p), "%s pool entry %s exists" % [id, p])
			check(p != id, "%s pool excludes itself" % id)
			check(not pool_seen.has(p), "%s pool entry %s not duplicated" % [id, p])
			pool_seen[p] = true
	for cat in SignCatalog.CATEGORIES:
		check(SignCatalog.by_category(cat).size() >= 4, "category %s has >= 4 signs" % cat)
	check(not SignCatalog.has_sign("nope"), "unknown id is rejected")
	check(SignCatalog.index_of("stop") == 0, "index_of")
	# The brief's must-have families are present.
	for must in ["stop", "give_way", "priority_road", "no_entry", "speed_30", "no_parking", "no_stopping",
			"no_overtaking", "roundabout", "one_way", "ped_crossing", "children", "roadworks", "slippery",
			"curve_left", "crossroads", "traffic_lights", "level_crossing", "cattle", "falling_rocks", "end_restrictions"]:
		check(SignCatalog.has_sign(must), "has " + must)


func _texts(rows: Dictionary) -> void:
	var used := {}
	for lang in ["en", "es"]:
		var actions := {}
		for id in SignCatalog.ids():
			for key in [SignCatalog.name_key(id), SignCatalog.action_key(id), SignCatalog.explain_key(id)]:
				used[key] = true
				check(rows.has(key), "missing key " + key)
				if rows.has(key):
					var t: String = rows[key][lang]
					check(t.strip_edges() != "", "%s has %s text" % [key, lang])
					check(t.length() <= 140, "%s %s text short enough (%d)" % [key, lang, t.length()])
			var a: String = rows.get(SignCatalog.action_key(id), {}).get(lang, "")
			check(a.length() <= 44, "%s %s action fits a button (%d chars)" % [id, lang, a.length()])
			check(not actions.has(a), "%s action '%s' unique (clashes with %s)" % [lang, a, actions.get(a, "")])
			actions[a] = id
	# No orphan sign texts left behind.
	for key in rows:
		if key.length() > 2 and key[1] == "_" and key[0] in ["S", "A", "E"]:
			check(used.has(key), "orphan sign text " + key)
	# Translations actually load.
	TranslationServer.set_locale("es")
	check(TranslationServer.translate("A_STOP") == rows["A_STOP"]["es"], "es translation loads")
	TranslationServer.set_locale("en")
	check(TranslationServer.translate("A_STOP") == rows["A_STOP"]["en"], "en translation loads")


func _ui_keys(rows: Dictionary) -> void:
	var src := FileAccess.get_file_as_string("res://scripts/main.gd")
	var re := RegEx.create_from_string("tr\\(\"([A-Z_]+)\"\\)")
	var n := 0
	for m in re.search_all(src):
		n += 1
		check(rows.has(m.get_string(1)), "UI key %s in strings.csv" % m.get_string(1))
	check(n > 20, "found UI keys in main.gd (%d)" % n)
	# printf-style keys keep their placeholders in both languages.
	for key in rows:
		var en: String = rows[key].en
		var es: String = rows[key].es
		check(en.count("%d") == es.count("%d") and en.count("%s") == es.count("%s"), "placeholders match in " + key)
