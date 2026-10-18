class_name BabelGame
extends RefCounted
## One 10-round game: which clip plays each round, the language choices
## shown, the answers given, score and streak. Deterministic for a seed.
##
## Scoring: a right answer is worth BASE[mode] × multiplier, where the
## multiplier is the current streak of right answers (1, 2, 3 … capped at
## MAX_MULT). A wrong answer scores 0 and resets the streak.

const ROUNDS := 10
const EASY := 0
const HARD := 1
const CHOICES := [4, 6]
const BASE := [100, 150]
const MAX_MULT := 5
const MODE_KEYS := ["easy", "hard"]

var mode := EASY
var seed_value := 0
var clip_ids: Array[String] = []
var choices: Array = []          # per round: Array[String] of language codes
var answers: Array[String] = []  # language code picked per answered round
var points: Array[int] = []      # points earned per answered round
var score := 0
var streak := 0
var best_streak := 0


static func create(bank: ClipBank, game_mode: int, seed_in: int, avoid: Array = []) -> BabelGame:
	var g := BabelGame.new()
	g.mode = clampi(game_mode, EASY, HARD)
	g.seed_value = seed_in
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("babel-ear:%d:%d" % [seed_in, g.mode])
	var langs: Array[String] = bank.playable.duplicate()
	_shuffle(langs, rng)
	# One language per round while there are enough; otherwise cycle.
	var order: Array[String] = []
	while order.size() < ROUNDS and not langs.is_empty():
		for code in langs:
			if order.size() < ROUNDS:
				order.append(code)
		_shuffle(langs, rng)
	var used := {}
	for code in order:
		var pool: Array = bank.by_lang[code].filter(func(id): return not used.has(id))
		var fresh: Array = pool.filter(func(id): return not (id in avoid))
		var pick_from: Array = fresh if not fresh.is_empty() else pool
		var id: String = pick_from[rng.randi_range(0, pick_from.size() - 1)]
		used[id] = true
		g.clip_ids.append(id)
		g.choices.append(choices_for(bank, code, g.mode, rng))
	return g


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


## Easy: the truth plus languages from other families, each family once
## ("very different"). Hard: the truth plus up to 3 close relatives, then
## random fill. Always distinct, always contains the truth.
static func choices_for(bank: ClipBank, truth: String, game_mode: int, rng: RandomNumberGenerator) -> Array[String]:
	var n: int = mini(CHOICES[game_mode], bank.playable.size())
	var out: Array[String] = [truth]
	var others: Array[String] = []
	for c in bank.playable:
		if c != truth:
			others.append(c)
	_shuffle(others, rng)
	if game_mode == EASY:
		var families := {bank.family_of(truth): true}
		for c in others:
			if out.size() >= n:
				break
			if not families.has(bank.family_of(c)):
				families[bank.family_of(c)] = true
				out.append(c)
	else:
		var rel := bank.relatives_of(truth)
		_shuffle(rel, rng)
		for c in rel:
			if out.size() >= mini(n, 4):
				break
			out.append(c)
	for c in others:  # fill (rarely needed in Easy; always in Hard)
		if out.size() >= n:
			break
		if not (c in out):
			out.append(c)
	_shuffle(out, rng)
	return out


func mode_key() -> String:
	return MODE_KEYS[mode]


func round_index() -> int:
	return answers.size()


func is_over() -> bool:
	return answers.size() >= ROUNDS


func current_clip() -> String:
	return "" if is_over() else clip_ids[answers.size()]


func current_choices() -> Array:
	return [] if is_over() else choices[answers.size()]


func truth_of(i: int, bank: ClipBank) -> String:
	return str(bank.by_id[clip_ids[i]]["language"])


func correct_count(bank: ClipBank) -> int:
	var n := 0
	for i in answers.size():
		if answers[i] == truth_of(i, bank):
			n += 1
	return n


static func multiplier_for(streak_after: int) -> int:
	return clampi(streak_after, 1, MAX_MULT)


## Records an answer for the current round. Returns
## {correct, truth, picked, points, multiplier, streak}.
func answer(code: String, bank: ClipBank) -> Dictionary:
	if is_over():
		return {}
	var truth := truth_of(answers.size(), bank)
	var ok := code == truth
	var pts := 0
	var mult := 1
	if ok:
		streak += 1
		best_streak = maxi(best_streak, streak)
		mult = multiplier_for(streak)
		pts = BASE[mode] * mult
	else:
		streak = 0
	score += pts
	answers.append(code)
	points.append(pts)
	return {"correct": ok, "truth": truth, "picked": code, "points": pts,
		"multiplier": mult, "streak": streak}


func to_dict() -> Dictionary:
	return {"v": 1, "mode": mode, "seed": seed_value, "clips": clip_ids.duplicate(),
		"choices": choices.duplicate(true), "answers": answers.duplicate(),
		"points": points.duplicate(), "score": score, "streak": streak, "best_streak": best_streak}


## Returns null when the dictionary is not a valid game for this bank.
static func from_dict(d: Dictionary, bank: ClipBank) -> BabelGame:
	if int(d.get("v", 0)) != 1:
		return null
	var g := BabelGame.new()
	g.mode = clampi(int(d.get("mode", 0)), EASY, HARD)
	g.seed_value = int(d.get("seed", 0))
	var cl = d.get("clips", [])
	var ch = d.get("choices", [])
	if not (cl is Array and ch is Array) or cl.size() != ROUNDS or ch.size() != ROUNDS:
		return null
	for i in ROUNDS:
		if not bank.by_id.has(str(cl[i])) or not (ch[i] is Array):
			return null
		var row: Array[String] = []
		for c in ch[i]:
			row.append(str(c))
		if not (str(bank.by_id[str(cl[i])]["language"]) in row):
			return null
		g.clip_ids.append(str(cl[i]))
		g.choices.append(row)
	for a in d.get("answers", []):
		g.answers.append(str(a))
	for p in d.get("points", []):
		g.points.append(int(p))
	if g.answers.size() > ROUNDS or g.points.size() != g.answers.size():
		return null
	g.score = int(d.get("score", 0))
	g.streak = int(d.get("streak", 0))
	g.best_streak = int(d.get("best_streak", 0))
	return g
