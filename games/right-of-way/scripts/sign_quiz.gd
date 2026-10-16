class_name SignQuiz
extends RefCounted
## Question generator: picks a sign (never one of the last NO_REPEAT), then
## builds 3-4 distinct choices — the sign's own action exactly once plus
## distractors from its pool (topped up from the same category if needed).
## Missed signs come back sooner so the run doubles as practice.

const NO_REPEAT := 10
const MISSED_CHANCE := 0.35

var rng := RandomNumberGenerator.new()
var history: Array[String] = []
var missed: Array[String] = []
var asked := 0


func _init(seed_value: int = -1) -> void:
	if seed_value < 0:
		rng.randomize()
	else:
		rng.seed = seed_value


func next_question(n_choices: int) -> Dictionary:
	var id := _pick_sign()
	history.append(id)
	while history.size() > NO_REPEAT:
		history.pop_front()
	asked += 1
	return build_question(id, n_choices, rng)


func mark_missed(id: String) -> void:
	if not missed.has(id):
		missed.append(id)


func _pick_sign() -> String:
	var candidates: Array[String] = []
	for id in SignCatalog.ids():
		if not history.has(id):
			candidates.append(id)
	if not missed.is_empty() and rng.randf() < MISSED_CHANCE:
		for id in missed:
			if candidates.has(id):
				missed.erase(id)
				return id
	return candidates[rng.randi_range(0, candidates.size() - 1)]


## Returns {id, choices: Array[String] of action keys (= sign ids), answer: index}.
static func build_question(id: String, n_choices: int, r: RandomNumberGenerator) -> Dictionary:
	var sign := SignCatalog.get_sign(id)
	var choices: Array[String] = [id]
	var pool: Array = sign.pool.duplicate()
	_shuffle(pool, r)
	for a in pool:
		if choices.size() >= n_choices:
			break
		if not choices.has(a) and SignCatalog.has_sign(a):
			choices.append(a)
	if choices.size() < n_choices:
		var extra: Array = SignCatalog.by_category(sign.cat)
		_shuffle(extra, r)
		var rest: Array = SignCatalog.ids()
		_shuffle(rest, r)
		extra.append_array(rest)
		for a in extra:
			if choices.size() >= n_choices:
				break
			if not choices.has(a):
				choices.append(a)
	_shuffle(choices, r)
	return {"id": id, "choices": choices, "answer": choices.find(id)}


static func _shuffle(arr: Array, r: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t
