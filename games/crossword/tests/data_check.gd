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


func _initialize() -> void:
	var ids := {}
	for lang in ["en", "es"]:
		var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/puzzles_%s.json" % lang))
		check(raw is Array, "%s pack parses" % lang)
		var pack := Pack.load_pack(lang)
		check(pack.size() >= 40, "%s has >= 40 puzzles (%d)" % [lang, pack.size()])
		var fives := 0
		var sevens := 0
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
				check(e.answer.length() >= 2, name + " length >= 2")
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
		print("%s: %d puzzles (%d 5x5, %d 7x7), %d entries" % [lang, pack.size(), fives, sevens, total])
	# Spanish uses Ñ somewhere; no accents anywhere in grids.
	var es := Pack.load_pack("es")
	var has_n := false
	for p in es:
		for s in p.solution:
			has_n = has_n or s == "Ñ"
			check(not "ÁÉÍÓÚÜ".contains(s) or s == "", "no accented letters in ES grids")
	check(has_n, "some ES puzzle uses Ñ")
	# daily pick covers the pack
	for lang in ["en", "es"]:
		var n := Pack.load_pack(lang).size()
		var seen := {}
		for day in n:
			seen[Pack.daily_index(20000 + day, n)] = true
		check(seen.size() == n, "%s daily pick cycles through every puzzle" % lang)
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
