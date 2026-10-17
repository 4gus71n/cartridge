extends SceneTree
## Question generation: the right action appears exactly once, choices are
## distinct real signs, sizes 3/4, no repeat within NO_REPEAT, missed signs
## come back, and seeds are deterministic.

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	_every_sign()
	_no_repeat()
	_missed_return()
	_determinism()
	_coverage()
	print("quiz_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _valid(q: Dictionary, n: int) -> bool:
	var ch: Array = q.choices
	if ch.size() != n or q.answer < 0 or q.answer >= n or ch[q.answer] != q.id:
		return false
	if ch.count(q.id) != 1:
		return false
	var seen := {}
	for c in ch:
		if seen.has(c) or not SignCatalog.has_sign(c):
			return false
		seen[c] = true
	return true


func _every_sign() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 42
	var bad := 0
	var related := 0
	var total := 0
	for id in SignCatalog.ids():
		for n in [3, 4]:
			for k in 25:
				var q := SignQuiz.build_question(id, n, r)
				if not _valid(q, n):
					bad += 1
					printerr("bad question ", q)
				var pool: Array = SignCatalog.get_sign(id).pool
				for c in q.choices:
					if c != id:
						total += 1
						if pool.has(c):
							related += 1
	check(bad == 0, "every sign x {3,4} choices x 25 draws is valid (%d bad)" % bad)
	check(related == total, "distractors come from the related pool (%d/%d)" % [related, total])


func _no_repeat() -> void:
	var quiz := SignQuiz.new(7)
	var last: Array[String] = []
	var repeats := 0
	var bad := 0
	for i in 2000:
		var n := 3 if i % 2 == 0 else 4
		var q := quiz.next_question(n)
		if not _valid(q, n):
			bad += 1
		if last.has(q.id):
			repeats += 1
		last.append(q.id)
		if last.size() > SignQuiz.NO_REPEAT:
			last.pop_front()
		if i % 9 == 0:
			quiz.mark_missed(q.id) # missed signs must still respect the window
	check(bad == 0, "2000 generated questions valid")
	check(repeats == 0, "no sign repeats within %d questions (%d repeats)" % [SignQuiz.NO_REPEAT, repeats])
	check(quiz.asked == 2000, "asked counter")


func _missed_return() -> void:
	# A missed sign reappears much sooner than chance would bring it back.
	var gaps := 0.0
	var trials := 60
	for t in trials:
		var quiz := SignQuiz.new(100 + t)
		var q := quiz.next_question(4)
		var id: String = q.id
		quiz.mark_missed(id)
		var gap := 0
		for i in 400:
			gap += 1
			if quiz.next_question(4).id == id:
				break
		gaps += gap
	var avg := gaps / trials
	check(avg < SignCatalog.count() * 0.6, "missed signs return early (avg gap %.1f)" % avg)
	check(avg > SignQuiz.NO_REPEAT, "but never inside the no-repeat window (avg gap %.1f)" % avg)
	var quiz2 := SignQuiz.new(1)
	quiz2.mark_missed("stop")
	quiz2.mark_missed("stop")
	check(quiz2.missed.size() == 1, "mark_missed dedupes")


func _determinism() -> void:
	var a := SignQuiz.new(99)
	var b := SignQuiz.new(99)
	var same := true
	for i in 50:
		var qa := a.next_question(4)
		var qb := b.next_question(4)
		if qa.id != qb.id or qa.choices != qb.choices:
			same = false
	check(same, "same seed -> same questions")


func _coverage() -> void:
	var quiz := SignQuiz.new(5)
	var seen := {}
	for i in 600:
		seen[quiz.next_question(4).id] = true
	check(seen.size() == SignCatalog.count(), "600 questions cover every sign (%d/%d)" % [seen.size(), SignCatalog.count()])
	var answers := {}
	for i in 400:
		answers[quiz.next_question(4).answer] = true
	check(answers.size() == 4, "correct answer lands in every button slot")
