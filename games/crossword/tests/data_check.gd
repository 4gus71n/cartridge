extends SceneTree
## Validates every bundled pack: counts and sizes, letters, entry lengths,
## clues for every entry (and no stray clues), crossing consistency, no
## duplicate answers / grids, clue never contains its own answer, ids unique.

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


## True when the clue simply hands over the answer (or an obvious stem of it).
func _gives_away(clue: String, answer: String) -> bool:
	var c := clue.to_lower()
	var a := answer.to_lower()
	if a.length() >= 3 and c.contains(a):
		return true
	if a.length() >= 5 and c.contains(a.substr(0, a.length() - 1)):
		return true
	return false


func _initialize() -> void:
	var ids := {}
	for lang in ["en", "es"]:
		var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/puzzles_%s.json" % lang))
		check(raw is Array, "%s pack parses" % lang)
		var pack := Pack.load_pack(lang)
		check(pack.size() >= 40, "%s has >= 40 puzzles (%d)" % [lang, pack.size()])
		var fives := 0
		var sevens := 0
		var answer_uses := {}   # ANSWER -> times used in this language pack
		var clue_texts := {}    # lowercased clue -> true
		# Packs rebuilt by tools/build.py tag every puzzle with its tier. The
		# older hand-made pack does not, and is held to the v1 rules until it is
		# rebuilt (see tools/wip/README.md).
		var rebuilt: bool = raw.size() > 0 and (raw[0] as Dictionary).has("tier")
		var grids := {}
		var short := 0
		var total := 0
		var letters := "ABCDEFGHIJKLMNOPQRSTUVWXYZ" + ("Ñ" if lang == "es" else "")
		for k in pack.size():
			var p := pack[k]
			var d: Dictionary = raw[k]
			var tag := p.id
			check(not ids.has(p.id), "%s id unique" % tag)
			ids[p.id] = true
			check(p.id.begins_with(lang + "-"), "%s id prefixed with language" % tag)
			for row in d.grid:
				check((row as String).length() == p.width, "%s rectangular" % tag)
			check(p.width == p.height and (p.width == 5 or p.width == 7), "%s is 5x5 or 7x7" % tag)
			if p.width == 5:
				fives += 1
			else:
				sevens += 1
			var key := "".join(d.grid)
			check(not grids.has(key), "%s grid not duplicated" % tag)
			grids[key] = true
			# letters
			for i in p.cell_count():
				if not p.is_block(i):
					check(letters.contains(p.solution[i]), "%s cell %d letter '%s' allowed" % [tag, i, p.solution[i]])
					check(p.across_of[i] >= 0 or p.down_of[i] >= 0, "%s cell %d in some entry" % [tag, i])
			# entries
			var answers := {}
			var numbers := {"across": {}, "down": {}}
			for e in p.entries:
				total += 1
				var name := "%s %d%s" % [tag, e.number, "A" if e.dir == Puzzle.ACROSS else "D"]
				if rebuilt:
					check(e.answer.length() >= 3, name + " length >= 3 (no 2-letter entries)")
				answer_uses[e.answer] = int(answer_uses.get(e.answer, 0)) + 1
				var ct: String = str(e.clue).strip_edges().to_lower()
				if rebuilt:
					check(not clue_texts.has(ct), "%s clue text is unique in the pack (%s)" % [name, e.clue])
					check(not _gives_away(e.clue, e.answer),
						"%s clue does not contain the answer (%s / %s)" % [name, e.answer, e.clue])
				clue_texts[ct] = true
				if e.answer.length() < 3:
					short += 1
				check(e.clue.strip_edges() != "", name + " has a clue")
				check(e.clue.length() <= 60, name + " clue fits the bar (<= 60 chars)")
				check(not answers.has(e.answer), name + " answer not repeated in puzzle (%s)" % e.answer)
				answers[e.answer] = true
				numbers["across" if e.dir == Puzzle.ACROSS else "down"][str(e.number)] = true
				check(not _words(e.clue).has(e.answer), name + " clue does not contain the answer")
				# crossing consistency: each letter equals the grid cell and the crossing entry agrees
				for j in e.cells.size():
					var cell: int = e.cells[j]
					check(e.answer.substr(j, 1) == p.solution[cell], name + " letter matches grid")
					var other := p.entry_at(cell, 1 - e.dir)
					if other >= 0:
						var oe: Dictionary = p.entries[other]
						check(oe.answer.substr(oe.cells.find(cell), 1) == e.answer.substr(j, 1), name + " crossing agrees")
			for dir_name in ["across", "down"]:
				for n in (d.get(dir_name, {}) as Dictionary).keys():
					check(numbers[dir_name].has(str(n)), "%s no stray %s clue %s" % [tag, dir_name, n])
		check(fives >= 30, "%s mostly 5x5 (%d)" % [lang, fives])
		check(sevens >= 3, "%s has some 7x7 (%d)" % [lang, sevens])
		check(short * 10 <= total, "%s entries >= 3 letters preferred (%d of %d short)" % [lang, short, total])
		# The headline complaint about v1 was repeated words, so this is the rule:
		# an answer of 4+ letters appears ONCE in a language pack; 3-letter
		# answers (the glue a small grid cannot avoid) at most three times, and
		# every clue text in the pack is different.
		var repeats := []
		for a in (answer_uses if rebuilt else {}):
			var cap := 3 if (a as String).length() == 3 else 1
			if int(answer_uses[a]) > cap:
				repeats.append("%s x%d" % [a, answer_uses[a]])
		repeats.sort()
		check(repeats.is_empty(), "%s has no over-used answers (%s)" % [lang, ", ".join(repeats)])
		var shipped := 0
		for t in Pack.TIERS:
			if Pack.tier_indices(pack, t).size() > 0:
				shipped += 1
		check(shipped > 0, "%s ships at least one tier" % lang)
		var distinct := answer_uses.size()
		print("%s: %d puzzles (%d 5x5, %d 7x7), %d entries, %d distinct answers%s"
			% [lang, pack.size(), fives, sevens, total, distinct,
				"" if rebuilt else "  [v1 pack, rebuild pending]"])
	# Spanish uses Ñ somewhere; no accents anywhere in grids.
	var es := Pack.load_pack("es")
	var has_n := false
	for p in es:
		for s in p.solution:
			has_n = has_n or s == "Ñ"
			check(not "ÁÉÍÓÚÜ".contains(s) or s == "", "no accented letters in ES grids")
	check(has_n, "some ES puzzle uses Ñ")
	# daily pick covers each shipped tier (see flow_check.gd for the full
	# tier/weekday/cycling coverage); this is just a smoke check here.
	for lang in ["en", "es"]:
		var pack := Pack.load_pack(lang)
		for t in Pack.TIERS:
			var idx := Pack.tier_indices(pack, t)
			if idx.is_empty():
				continue
			var seen := {}
			var day := 20000
			var guard := 0
			while seen.size() < idx.size() and guard < 20000:
				if Pack.daily_tier(day) == t:
					seen[Pack.daily_index(pack, day)] = true
				day += 1
				guard += 1
			check(seen.size() == idx.size(), "%s %s daily pick cycles through every puzzle" % [lang, t])
	check(Pack.format_time(75.4) == "1:15", "format_time")
	print("data_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _words(clue: String) -> Array:
	var out := []
	var cur := ""
	var up := clue.to_upper()
	for i in up.length():
		var ch := up.substr(i, 1)
		var base := ch
		var map := {"Á": "A", "É": "E", "Í": "I", "Ó": "O", "Ú": "U", "Ü": "U"}
		if map.has(ch):
			base = map[ch]
		if ("ABCDEFGHIJKLMNOPQRSTUVWXYZÑ").contains(base):
			cur += base
		else:
			if cur != "":
				out.append(cur)
			cur = ""
	if cur != "":
		out.append(cur)
	return out
