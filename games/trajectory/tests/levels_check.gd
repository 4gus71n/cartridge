extends SceneTree
## Level data validity: every level is solved by its ideal answer, the
## starting state does not already solve it, and the content is sane.

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	var total := 0
	for w in Levels.WORLDS:
		total += w.count
	check(total == Levels.count(), "world sizes add up to the level count")
	check(Levels.count() >= 30, "at least 30 levels (got %d)" % Levels.count())
	check(Levels.world_of(0) == 0 and Levels.world_of(Levels.count() - 1) == Levels.WORLDS.size() - 1,
		"world_of covers the ends")
	check(Levels.world_start(1) == Levels.WORLDS[0].count, "world_start")
	var intros := {}
	for i in Levels.count():
		_check_level(i, Levels.get_level(i))
		var key: String = Levels.get_level(i).get("intro", "")
		if key != "":
			check(not intros.has(key), "intro %s used once" % key)
			intros[key] = true
	check(Levels.get_level(0).has("intro"), "first level teaches")
	for w in Levels.WORLDS.size():
		check(Levels.get_level(Levels.world_start(w)).has("intro"), "world %d opens with a blurb" % (w + 1))
	_check_translations(intros)
	print("levels_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _check_level(i: int, lvl: Dictionary) -> void:
	var tag := "level %d" % (i + 1)
	check(lvl.form == "free" or Forms.SPECS.has(lvl.form), "%s: known form" % tag)
	check(lvl.targets.size() >= 2, "%s: has targets" % tag)
	check(lvl.has("preview"), "%s: preview flag" % tag)
	# Ideal answer solves it.
	var ideal := MathExpr.parse(Levels.ideal_expr(lvl))
	check(ideal.ok, "%s: ideal parses" % tag)
	var res := Flight.simulate(ideal, lvl)
	check(res.success, "%s: ideal %s solves it (crash %s #%d, missed %d)" % [tag, Levels.ideal_expr(lvl),
		res.crash, res.crash_index, Flight.missed_count(res)])
	# Stepper levels: ideal values are reachable with the steppers, and the
	# initial values are not already a solution.
	if lvl.form != "free":
		var ps := Forms.params_for(lvl)
		check(ps.size() == lvl.ideal.size(), "%s: ideal has every param" % tag)
		for p in ps:
			var v := float(lvl.ideal.get(p.name, INF))
			check(v >= p.min and v <= p.max, "%s: %s within range" % [tag, p.name])
			var steps: float = (v - p.min) / p.step
			check(absf(steps - roundf(steps)) < 1e-6, "%s: %s on the step grid" % [tag, p.name])
			if p.locked:
				check(is_equal_approx(v, p.init), "%s: locked %s matches ideal" % [tag, p.name])
		var start := MathExpr.parse(Forms.expr(lvl.form, Forms.initial_values(lvl)))
		check(not Flight.simulate(start, lvl).success, "%s: starting values do not solve it" % tag)
	else:
		check(not MathExpr.parse("").ok, "%s: empty keypad does not launch" % tag)
	# Content sanity: everything inside the plot, targets not inside obstacles,
	# and targets are not trivially solved by y = 0.
	var plot := Rect2(Flight.X_MIN, Flight.Y_MIN, Flight.X_MAX - Flight.X_MIN, Flight.Y_MAX - Flight.Y_MIN)
	for t in lvl.targets:
		var tp := Vector2(t[0], t[1])
		check(plot.has_point(tp), "%s: target %s inside plot" % [tag, tp])
		for r in lvl.get("rocks", []):
			check(tp.distance_to(Vector2(r[0], r[1])) > r[2] + Flight.TARGET_R, "%s: target clear of rock" % tag)
		for w in lvl.get("walls", []):
			check(not Flight.wall_rect(w).grow(Flight.TARGET_R).has_point(tp), "%s: target clear of wall" % tag)
	for r in lvl.get("rocks", []):
		check(plot.has_point(Vector2(r[0], r[1])), "%s: rock inside plot" % tag)
	check(not Flight.simulate(MathExpr.parse("0"), lvl).success, "%s: y = 0 does not solve it" % tag)
	# The pretty ideal is printable.
	check(Levels.ideal_pretty(lvl) != "", "%s: ideal display" % tag)


func _check_translations(intros: Dictionary) -> void:
	var f := FileAccess.open("res://i18n/strings.csv", FileAccess.READ)
	check(f != null, "strings.csv readable")
	if f == null:
		return
	var keys := {}
	var header := f.get_csv_line()
	check(header.size() == 3 and header[1] == "en" and header[2] == "es", "csv header keys,en,es")
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 3:
			continue
		check(row[1] != "" and row[2] != "", "both languages for %s" % row[0])
		keys[row[0]] = true
	for k in intros:
		check(keys.has("INTRO_%s_T" % k) and keys.has("INTRO_%s" % k), "intro strings for %s" % k)
	for w in Levels.WORLDS:
		check(keys.has(w.key) and keys.has(w.key + "_SUB"), "world strings for %s" % w.key)
	for e in ["ERR_EMPTY", "ERR_INCOMPLETE", "ERR_UNEXPECTED", "ERR_PAREN", "ERR_PAREN_CLOSE",
			"ERR_NUMBER", "ERR_CHAR", "ERR_FN_PAREN"]:
		check(keys.has(e), "error string %s" % e)
