extends SceneTree
## Rules: round building (no duplicate clip, truth always offered, distinct
## choices, Easy = different families, Hard = close relatives), determinism,
## scoring + streak multiplier, serialisation. Runs on a synthetic bank and
## on the real bundled bank.

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	_synthetic()
	_real_bank_sweep()
	_scoring()
	_serialisation()
	print("game_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _lang(fam: String, rel: Array) -> Dictionary:
	return {"name_en": fam, "name_es": fam, "family": fam, "relatives": rel}


func _tiny_bank(per_lang: int, codes: Array, min_clips := 6) -> ClipBank:
	var info := {}
	var fams := {"a1": "fa", "a2": "fa", "a3": "fa", "b1": "fb", "b2": "fb", "c1": "fc", "d1": "fd", "e1": "fe", "f1": "ff"}
	for code in codes:
		info[code] = _lang(fams.get(code, code), [])
	info["a1"]["relatives"] = ["a2", "b1"]
	var clips := []
	for code in codes:
		for i in per_lang:
			clips.append({"id": "%s_%02d" % [code, i], "language": code, "file": "x.ogg", "duration": 6.0})
	return ClipBank.from_data(clips, info, min_clips)


func _validate(g: BabelGame, bank: ClipBank, tag: String) -> void:
	check(g.clip_ids.size() == BabelGame.ROUNDS, tag + ": 10 rounds")
	check(g.choices.size() == BabelGame.ROUNDS, tag + ": 10 choice rows")
	var seen := {}
	for id in g.clip_ids:
		check(not seen.has(id), tag + ": no duplicate clip " + id)
		seen[id] = true
	var want: int = mini(BabelGame.CHOICES[g.mode], bank.playable.size())
	for i in BabelGame.ROUNDS:
		var row: Array = g.choices[i]
		var truth := g.truth_of(i, bank)
		check(truth in row, tag + ": truth offered round %d" % i)
		check(row.size() == want, tag + ": %d choices (got %d)" % [want, row.size()])
		var uniq := {}
		for c in row:
			uniq[c] = true
			check(c in bank.playable, tag + ": choice is playable")
		check(uniq.size() == row.size(), tag + ": distinct choices round %d" % i)


func _synthetic() -> void:
	var codes := ["a1", "a2", "a3", "b1", "b2", "c1", "d1", "e1", "f1"]
	var bank := _tiny_bank(6, codes)
	check(bank.playable.size() == 9, "synthetic bank has 9 playable languages")
	var thin := _tiny_bank(5, codes)
	check(thin.playable.is_empty(), "languages below MIN_CLIPS are not playable")
	check(bank.relatives_of("a1") == ["a2", "b1", "a3"], "relatives: explicit first, then family (%s)" % [bank.relatives_of("a1")])
	for s in 40:
		for m in [BabelGame.EASY, BabelGame.HARD]:
			var g := BabelGame.create(bank, m, s)
			_validate(g, bank, "synthetic s%d m%d" % [s, m])
			# 9 languages < 10 rounds: all 9 used, one repeats.
			var langs := {}
			for i in 10:
				langs[g.truth_of(i, bank)] = true
			check(langs.size() == 9, "every language appears when fewer than 10")
			if m == BabelGame.EASY:
				for row in g.choices:
					var fams := {}
					for c in row:
						fams[bank.family_of(c)] = true
					check(fams.size() == row.size(), "easy: one language per family")
	# Hard mode always includes a relative of a1 when a1 is the answer.
	var found := 0
	for s in 60:
		var g := BabelGame.create(bank, BabelGame.HARD, s)
		for i in 10:
			if g.truth_of(i, bank) == "a1":
				found += 1
				var row: Array = g.choices[i]
				check("a2" in row and "b1" in row and "a3" in row, "hard: a1 offers its 3 relatives %s" % [row])
	check(found > 0, "hard relatives case exercised")
	# Determinism + avoid list.
	var g1 := BabelGame.create(bank, BabelGame.EASY, 77)
	var g2 := BabelGame.create(bank, BabelGame.EASY, 77)
	check(g1.clip_ids == g2.clip_ids and g1.choices == g2.choices, "same seed -> same game")
	var g3 := BabelGame.create(bank, BabelGame.EASY, 78)
	check(g1.clip_ids != g3.clip_ids, "different seed -> different game")
	var avoid := []
	for code in codes:
		for i in 5:
			avoid.append("%s_%02d" % [code, i])
	var g4 := BabelGame.create(bank, BabelGame.HARD, 5, avoid)
	var fresh := 0
	for id in g4.clip_ids:
		if not (id in avoid):
			fresh += 1
	check(fresh == 9, "avoid list: unheard clips preferred (%d fresh)" % fresh)
	# Tiny bank with only 3 languages: choices capped, still valid.
	var small := _tiny_bank(6, ["a1", "b1", "c1"])
	var g5 := BabelGame.create(small, BabelGame.HARD, 3)
	_validate(g5, small, "3-language bank")


func _real_bank_sweep() -> void:
	var bank := ClipBank.load_default()
	check(bank.playable.size() >= 10, "real bank: >= 10 playable languages (%d)" % bank.playable.size())
	if bank.playable.size() < 10:
		return
	var hard_rel := 0
	var hard_rounds := 0
	for s in 150:
		for m in [BabelGame.EASY, BabelGame.HARD]:
			var g := BabelGame.create(bank, m, s * 7919 + 13)
			_validate(g, bank, "real s%d m%d" % [s, m])
			var langs := {}
			for i in 10:
				langs[g.truth_of(i, bank)] = true
			check(langs.size() == 10, "real: 10 different languages per game")
			for i in 10:
				var truth := g.truth_of(i, bank)
				var row: Array = g.choices[i]
				if m == BabelGame.EASY:
					for c in row:
						if c != truth:
							check(bank.family_of(c) != bank.family_of(truth), "real easy: distractor %s not related to %s" % [c, truth])
				elif not bank.relatives_of(truth).is_empty():
					hard_rounds += 1
					for c in row:
						if c in bank.relatives_of(truth):
							hard_rel += 1
							break
	check(hard_rounds > 0 and hard_rel == hard_rounds, "real hard: every round with relatives offers one (%d/%d)" % [hard_rel, hard_rounds])


func _scoring() -> void:
	var bank := _tiny_bank(6, ["a1", "a2", "a3", "b1", "b2", "c1", "d1", "e1", "f1"])
	check(BabelGame.multiplier_for(0) == 1 and BabelGame.multiplier_for(1) == 1, "multiplier floor 1")
	check(BabelGame.multiplier_for(3) == 3 and BabelGame.multiplier_for(9) == BabelGame.MAX_MULT, "multiplier grows and caps")
	# All right, Easy: 100*(1+2+3+4+5+5+5+5+5+5) = 4000.
	var g := BabelGame.create(bank, BabelGame.EASY, 1)
	var total := 0
	for i in 10:
		var r := g.answer(g.truth_of(i, bank), bank)
		check(r["correct"] and r["streak"] == i + 1, "perfect: streak %d" % (i + 1))
		total += r["points"]
	check(g.score == 4000 and total == 4000, "perfect easy game = 4000 (got %d)" % g.score)
	check(g.is_over() and g.current_clip() == "" and g.answer("a1", bank).is_empty(), "no answers after round 10")
	check(g.best_streak == 10 and g.correct_count(bank) == 10, "best streak 10, 10 right")
	# Hard pattern: R R W R R R W W R R  -> 150*(1+2 +1+2+3 +1+2) = 1800
	var h := BabelGame.create(bank, BabelGame.HARD, 2)
	var pattern := [1, 1, 0, 1, 1, 1, 0, 0, 1, 1]
	for i in 10:
		var truth := h.truth_of(i, bank)
		var wrong: String = h.choices[i][0] if h.choices[i][0] != truth else h.choices[i][1]
		var r := h.answer(truth if pattern[i] else wrong, bank)
		check(r["correct"] == bool(pattern[i]), "pattern answer %d" % i)
		if not pattern[i]:
			check(r["points"] == 0 and r["streak"] == 0, "wrong resets streak, 0 points")
	check(h.score == 1800, "hard pattern score 1800 (got %d)" % h.score)
	check(h.best_streak == 3 and h.correct_count(bank) == 7, "pattern best streak 3, 7 right")
	check(h.points.size() == 10 and h.points[4] == 300, "per-round points recorded")
	# All wrong.
	var w := BabelGame.create(bank, BabelGame.EASY, 3)
	for i in 10:
		var truth := w.truth_of(i, bank)
		w.answer(w.choices[i][0] if w.choices[i][0] != truth else w.choices[i][1], bank)
	check(w.score == 0 and w.best_streak == 0, "all wrong = 0")


func _serialisation() -> void:
	var bank := _tiny_bank(6, ["a1", "a2", "a3", "b1", "b2", "c1", "d1", "e1", "f1"])
	var g := BabelGame.create(bank, BabelGame.HARD, 9)
	for i in 4:
		g.answer(g.truth_of(i, bank), bank)
	var d := g.to_dict()
	var copy := BabelGame.from_dict(JSON.parse_string(JSON.stringify(d)), bank)
	check(copy != null, "roundtrip through JSON")
	if copy:
		check(copy.clip_ids == g.clip_ids and copy.choices == g.choices, "clips + choices restored")
		check(copy.score == g.score and copy.streak == 4 and copy.round_index() == 4, "score/streak/round restored")
		check(copy.mode == BabelGame.HARD and copy.points == g.points, "mode + points restored")
		var r := copy.answer(copy.truth_of(4, bank), bank)
		check(r["multiplier"] == 5 and copy.score == 150 * 15, "streak continues after resume")
	check(BabelGame.from_dict({}, bank) == null, "empty dict rejected")
	var bad := d.duplicate(true)
	bad["clips"][0] = "nope_99"
	check(BabelGame.from_dict(bad, bank) == null, "unknown clip rejected")
	var bad2 := d.duplicate(true)
	bad2["choices"][1] = ["zz"]
	check(BabelGame.from_dict(bad2, bank) == null, "choices without truth rejected")
	var bad3 := d.duplicate(true)
	bad3["clips"].pop_back()
	check(BabelGame.from_dict(bad3, bank) == null, "wrong round count rejected")
	var bad4 := d.duplicate(true)
	bad4["points"] = [1]
	check(BabelGame.from_dict(bad4, bank) == null, "points/answers mismatch rejected")
