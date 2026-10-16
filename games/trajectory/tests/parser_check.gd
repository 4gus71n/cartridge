extends SceneTree
## Expression parser suite: godot --headless --path . --script tests/parser_check.gd

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func near(a: float, b: float, msg: String) -> void:
	check(absf(a - b) < 1e-9 * maxf(1.0, absf(b)), "%s (got %s, want %s)" % [msg, a, b])


func val(src: String, x: float) -> float:
	var e := MathExpr.parse(src)
	check(e.ok, "parses: %s (error %s)" % [src, e.error])
	return e.eval(x)


func _initialize() -> void:
	_numbers()
	_precedence()
	_unary_minus()
	_power_right_assoc()
	_implicit_multiplication()
	_functions_and_pi()
	_errors()
	_auto_close()
	_pretty()
	print("parser_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _numbers() -> void:
	near(val("42", 0), 42, "integer")
	near(val("3.25", 0), 3.25, "decimal")
	near(val(".5", 0), 0.5, "leading dot")
	near(val("x", 7), 7, "x")
	near(val("X", -2), -2, "upper-case X")
	near(val(" 2 + x ", 3), 5, "spaces ignored")


func _precedence() -> void:
	near(val("2+3*4", 0), 14, "* before +")
	near(val("(2+3)*4", 0), 20, "parentheses")
	near(val("10-4-3", 0), 3, "- is left-assoc")
	near(val("12/3/2", 0), 2, "/ is left-assoc")
	near(val("2*3^2", 0), 18, "^ before *")
	near(val("1+x^2", 3), 10, "^ before +")
	near(val("x^2-2x-3", 3), 0, "quadratic at a root")
	near(val("0.5x^2-x-4", 4), 0, "decimal coefficient quadratic")


func _unary_minus() -> void:
	near(val("-x^2", 3), -9, "-x^2 = -(x^2)")
	near(val("(-x)^2", 3), 9, "(-x)^2")
	near(val("-3", 0), -3, "negative literal")
	near(val("--2", 0), 2, "double negation")
	near(val("2*-x", 4), -8, "unary after *")
	near(val("2--x", 4), 6, "binary then unary minus")
	near(val("x^-1", 4), 0.25, "negative exponent")
	near(val("-2x", 3), -6, "-2x")
	near(val("+x", 3), 3, "unary plus")
	near(val("x−1", 3), 2, "typographic minus")


func _power_right_assoc() -> void:
	near(val("2^3^2", 0), 512, "2^3^2 = 2^(3^2)")
	near(val("(2^3)^2", 0), 64, "(2^3)^2")
	near(val("x^2^-1", 16), 4, "16^(2^-1) = 4")
	near(val("(-2)^3", 0), -8, "odd power of a negative base")


func _implicit_multiplication() -> void:
	near(val("2x", 5), 10, "2x")
	near(val("2x^2", 3), 18, "2x^2 = 2*(x^2)")
	near(val("3(x+1)", 1), 6, "3(x+1)")
	near(val("x(x-3)(x+3)/4", 4), 7, "x(x-3)(x+3)/4")
	near(val("(x+1)(x-1)", 3), 8, "(x+1)(x-1)")
	near(val("2sin(x)", PI / 2), 2, "2sin(x)")
	near(val("2pi", 0), TAU, "2pi")
	near(val("1/2x", 4), 2, "1/2x = (1/2)*x")
	near(val("xx", 3), 9, "xx")
	check(not MathExpr.parse("x2").ok, "x2 is rejected (ambiguous)")
	check(not MathExpr.parse("(x)3").ok, "(x)3 is rejected")


func _functions_and_pi() -> void:
	near(val("sin(x)", PI / 2), 1, "sin")
	near(val("cos(0)", 0), 1, "cos")
	near(val("3sin(x)+1", -PI / 2), -2, "3sin(x)+1")
	near(val("π", 0), PI, "π glyph")
	near(val("sin(pi x/2)", 1), 1, "implicit pi x")
	near(val("0.5x+2sin(x)", PI), PI / 2, "combo with sine")
	near(val("x×2÷4", 2), 1, "× and ÷ glyphs")


func _errors() -> void:
	var cases := {
		"": "ERR_EMPTY", "   ": "ERR_EMPTY", "2+": "ERR_INCOMPLETE", "*2": "ERR_UNEXPECTED",
		"(x+1": "ERR_PAREN", "x+1)": "ERR_PAREN_CLOSE", "1.2.3": "ERR_NUMBER", "2$": "ERR_CHAR",
		"sin x": "ERR_FN_PAREN", "()": "ERR_UNEXPECTED", "x^": "ERR_INCOMPLETE", "x2": "ERR_UNEXPECTED",
		".": "ERR_NUMBER", "2**x": "ERR_UNEXPECTED",
	}
	for src in cases:
		var e := MathExpr.parse(src)
		check(not e.ok, "'%s' must fail" % src)
		check(e.error == cases[src], "'%s' error %s (got %s)" % [src, cases[src], e.error])
		check(is_nan(e.eval(1.0)), "failed parse evaluates to NaN: '%s'" % src)
	var e := MathExpr.parse("x+1)")
	check(e.error_pos == 3, "error position points at the stray ')' (got %d)" % e.error_pos)
	# Division by zero gives a non-finite value (the flight treats it as a break).
	check(not is_finite(MathExpr.parse("1/x").eval(0.0)), "1/0 is not finite")
	check(is_nan(MathExpr.parse("x^0.5").eval(-4.0)), "sqrt of negative is NaN")


func _auto_close() -> void:
	check(MathExpr.open_parens("sin(2(x+1") == 2, "open paren count")
	var e := MathExpr.parse("sin(2(x+1", true)
	check(e.ok, "auto-close closes missing parens")
	near(e.eval(-1.0), 0, "auto-closed value")
	check(not MathExpr.parse("x+1)", true).ok, "auto-close does not fix extra ')'")


func _pretty() -> void:
	check(MathExpr.pretty("x^2-4") == "x²−4", "pretty x^2-4 (got %s)" % MathExpr.pretty("x^2-4"))
	check(MathExpr.pretty("2*x^3") == "2·x³", "pretty 2*x^3")
	check(MathExpr.pretty("x^25") == "x^25", "pretty keeps multi-digit exponents")
	check(MathExpr.pretty("2pi") == "2π", "pretty pi")
