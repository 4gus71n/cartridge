extends SceneTree
## Path / target / obstacle collision math + forms + polynomial helpers.

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func fly(src: String, level: Dictionary) -> Dictionary:
	return Flight.simulate(MathExpr.parse(src), level)


func _initialize() -> void:
	_geometry()
	_targets()
	_rocks()
	_walls()
	_undefined_and_offscreen()
	_forms()
	_poly()
	print("flight_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _geometry() -> void:
	var a := Vector2(0, 0)
	var b := Vector2(10, 0)
	check(is_equal_approx(Flight.seg_point_dist(a, b, Vector2(5, 3)), 3.0), "distance to segment middle")
	check(is_equal_approx(Flight.seg_point_dist(a, b, Vector2(-3, 4)), 5.0), "distance to segment end")
	check(Flight.seg_point_dist(a, a, Vector2(3, 4)) == 5.0, "degenerate segment")
	var r := Rect2(4, -1, 2, 2)
	check(Flight.seg_rect_entry(a, b, r) == Vector2(4, 0), "segment enters rect at its left side")
	check(Flight.seg_rect_entry(Vector2(0, 5), Vector2(10, 5), r) == null, "segment above rect misses")
	check(Flight.seg_rect_entry(Vector2(5, 0), Vector2(5.1, 0), r) == Vector2(5, 0), "segment starting inside")
	check(Flight.seg_rect_entry(Vector2(3, -3), Vector2(7, 3), r) != null, "diagonal crossing")
	check(Flight.seg_rect_entry(Vector2(0, 3), Vector2(3, 0), r) == null, "diagonal passing by")
	check(Flight.wall_rect([2, 5, 1, -5]) == Rect2(1, -5, 1, 10), "wall rect normalised")


func _targets() -> void:
	var lvl := {"targets": [[-5, 3], [5, 3]]}
	var res := fly("3", lvl)
	check(res.success, "y=3 hits both targets")
	check(res.hit_at[0] >= 0 and res.hit_at[0] < res.hit_at[1], "targets hit in order of x")
	check(fly("3.55", lvl).success, "passing within the target radius counts")
	var miss := fly("3.7", lvl)
	check(not miss.success and Flight.missed_count(miss) == 2, "passing outside the radius misses both")
	check(Flight.missed_count(fly("x-2", lvl)) == 1, "line through one target misses the other")
	# A steep segment between two samples still touches a target it crosses.
	check(fly("1000(x-0.011)", {"targets": [[0.011, 0]]}).success, "steep curve still crosses the target")
	check((fly("3", lvl).points as PackedVector2Array).size() == 1001, "full flight has 1001 samples")


func _rocks() -> void:
	var lvl := {"targets": [[-8, 0], [8, 0]], "rocks": [[0, 0, 1.0]]}
	var res := fly("0", lvl)
	check(not res.success and res.crash == Flight.Crash.ROCK and res.crash_index == 0, "line through rock crashes")
	check(res.hit_at[0] >= 0 and res.hit_at[1] == -1, "targets before the crash count, after don't")
	var cp: Vector2 = res.crash_point
	check(cp.x < 0 and cp.x > -1.3, "crash point on the rock's left (got %s)" % cp)
	var pts: PackedVector2Array = res.points
	check(pts[pts.size() - 1] == cp, "path ends at the crash point")
	check(fly("1.1", lvl).crash == Flight.Crash.ROCK, "1.1 above centre is within r + rocket")
	check(fly("1.2", lvl).crash == Flight.Crash.NONE, "1.2 above centre clears it")
	check(fly("0.15x^2-1.1", {"targets": [[0, -1.1]], "rocks": [[0, 0, 1.0]]}).crash == Flight.Crash.ROCK,
		"parabola under a rock clips it")


func _walls() -> void:
	var lvl := {"targets": [[-6, 2], [7, 2]], "walls": [[1, -10, 1.8, 0.6], [1, 3.4, 1.8, 10]]}
	check(fly("2", lvl).success, "flies through the gap")
	var low := fly("0", lvl)
	check(low.crash == Flight.Crash.WALL and low.crash_index == 0, "hits the lower wall")
	check(is_equal_approx(low.crash_point.x, 1.0 - Flight.ROCKET_R), "wall crash at the wall face")
	check(fly("4", lvl).crash_index == 1, "hits the upper wall")
	check(fly("0.5x+2", {"walls": [[-1, 5, 1, 6]]}).crash == Flight.Crash.NONE, "sloped line under wall")


func _undefined_and_offscreen() -> void:
	var res := fly("1/x", {"targets": [[5, 0.2]]})
	check(res.crash == Flight.Crash.UNDEFINED, "1/x breaks at x = 0")
	check(absf(res.crash_point.x) < 0.03, "break point at x≈0")
	var far := fly("x^9", {"targets": [[0, 0]], "rocks": [[9, 9, 1.0]]})
	check(far.success, "curve leaving the plot is fine (rock off its path)")
	check(fly("10000000000", {}).crash == Flight.Crash.NONE, "huge constant flies off-screen without crashing")
	check(Flight.simulate(MathExpr.parse("2+"), {"targets": [[0, 0]]}).crash == Flight.Crash.UNDEFINED,
		"invalid expression never succeeds")
	check(fly("x", {}).success, "no targets, no obstacles = success")


func _forms() -> void:
	var cases := [
		["c", {"c": 3.0}, "3"], ["c", {"c": -5.0}, "−5"],
		["mx", {"m": 1.0}, "x"], ["mx", {"m": -0.5}, "−0.5x"], ["mx", {"m": 0.0}, "0"],
		["mxb", {"m": 2.0, "b": -3.0}, "2x − 3"], ["mxb", {"m": -1.0, "b": 2.0}, "−x + 2"],
		["mxb", {"m": 0.0, "b": 4.0}, "4"], ["mxb", {"m": 1.5, "b": 0.0}, "1.5x"],
		["vertex", {"a": 1.0, "h": 2.0, "k": -3.0}, "(x − 2)² − 3"],
		["vertex", {"a": -0.25, "h": -1.0, "k": 0.0}, "−0.25(x + 1)²"],
		["vertex", {"a": 2.0, "h": 0.0, "k": 1.0}, "2x² + 1"],
		["std", {"a": 1.0, "b": -2.0, "c": -3.0}, "x² − 2x − 3"],
		["roots2", {"a": 0.5, "p": -4.0, "q": 2.0}, "0.5(x + 4)(x − 2)"],
		["roots3", {"a": 0.05, "p": -6.0, "q": 0.0, "r": 6.0}, "0.05x(x + 6)(x − 6)"],
		["roots3", {"a": -1.0, "p": 0.0, "q": 0.0, "r": 1.0}, "−x²(x − 1)"],
	]
	for c in cases:
		var got := Forms.pretty(c[0], c[1])
		check(got == c[2], "pretty %s %s -> '%s' (got '%s')" % [c[0], c[1], c[2], got])
		# expr() must agree numerically with what the pretty form says.
		var e := MathExpr.parse(Forms.expr(c[0], c[1]))
		var e2 := MathExpr.parse(got.replace("−", "-").replace("²", "^2").replace("³", "^3"))
		check(e.ok and e2.ok, "form expressions parse: %s" % got)
		for x in [-3.0, 0.5, 2.0]:
			check(absf(e.eval(x) - e2.eval(x)) < 1e-9, "expr/pretty agree for %s at %s" % [got, x])
	var colored := Forms.pretty("mxb", {"m": 2.0, "b": -3.0}, {"m": "#fff", "b": "#000"})
	check(colored == "[color=#fff]2[/color]x − [color=#000]3[/color]", "coloured pretty (got %s)" % colored)
	check(Forms.num(0.25) == "0.25" and Forms.num(-0.0) == "0" and Forms.num(3.0) == "3", "num formatting")
	var lvl := {"form": "mxb", "lock": {"m": 1}}
	var ps := Forms.params_for(lvl)
	check(ps.size() == 2 and ps[0].locked and ps[0].init == 1.0 and not ps[1].locked, "locks applied")


func _poly() -> void:
	var co := Poly.fit(MathExpr.parse("0.5(x-2)^2+3"))
	check(co.size() == 4, "vertex form is a polynomial")
	check(Poly.format(co) == "0.5x² − 2x + 5", "expanded vertex form (got %s)" % Poly.format(co))
	check(Poly.format(Poly.fit(MathExpr.parse("x(x-3)(x+3)/4"))) == "0.25x³ − 2.25x", "expanded cubic")
	check(Poly.format(Poly.fit(MathExpr.parse("-x+0"))) == "−x", "linear")
	check(Poly.format(Poly.fit(MathExpr.parse("7"))) == "7", "constant")
	check(Poly.fit(MathExpr.parse("sin(x)")).is_empty(), "sine is not a polynomial")
	check(Poly.fit(MathExpr.parse("x^4")).is_empty(), "degree 4 is rejected")
	check(Poly.fit(MathExpr.parse("1/(x-0.5)")).is_empty(), "rational is rejected")
