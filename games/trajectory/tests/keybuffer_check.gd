extends SceneTree
## Keypad buffer suite: token editing, backspace units, display, drafts.

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func typed(keys: Array) -> KeyBuffer:
	var b := KeyBuffer.new()
	for k in keys:
		b.press(k)
	return b


func _initialize() -> void:
	var b := typed(["2", "x", "sq", "-", "3", "x", "+", "1"])
	check(b.text() == "2x^2-3x+1", "typed text (got %s)" % b.text())
	check(KeyBuffer.display(b.text()) == "2x²−3x+1", "display (got %s)" % KeyBuffer.display(b.text()))
	var e := b.parse()
	check(e.ok and is_equal_approx(e.eval(2.0), 3.0), "typed formula evaluates")
	check(b.backspace() and b.text() == "2x^2-3x+", "backspace removes one token")
	b = typed(["x", "sq"])
	b.press("back")
	check(b.text() == "x", "backspace removes x² as one unit")
	b = typed(["3", "sin", "x"])
	check(b.text() == "3sin(x" and b.missing_parens() == 1, "sin( opens a paren")
	check(b.parse().ok and is_equal_approx(b.parse().eval(PI / 2), 3.0), "auto-closed sin parses")
	b.press("back")
	b.press("back")
	check(b.text() == "3", "backspace removes sin( as one unit")
	check(typed(["pi"]).parse().ok and KeyBuffer.display("2pi") == "2π", "pi key")
	check(KeyBuffer.display("x*2/4") == "x×2÷4", "× and ÷ in display")
	b = typed(["1", "2"])
	check(b.press("clear") and b.is_empty() and not b.press("clear"), "clear empties once")
	check(not b.backspace(), "backspace on empty does nothing")
	check(not b.press("?"), "unknown key ignored")
	b = KeyBuffer.new()
	for i in KeyBuffer.MAX_TOKENS + 5:
		b.press("1")
	check(b.tokens.size() == KeyBuffer.MAX_TOKENS, "length capped")
	# set_text round-trips the ideal answers of every keypad level.
	for i in Levels.count():
		var lvl: Dictionary = Levels.get_level(i)
		if lvl.form != "free":
			continue
		var kb := KeyBuffer.new()
		kb.set_text(lvl.ideal)
		check(kb.text() == lvl.ideal, "set_text round-trip %s" % lvl.ideal)
		for t in kb.tokens:
			var key: String = t if t == "(" else t.trim_suffix("(")
			check(KeyBuffer.INSERT.has(key), "token %s of level %d is on the keypad" % [t, i + 1])
	var sb := KeyBuffer.new()
	sb.set_text("sin(pi x)")
	check(sb.tokens == PackedStringArray(["sin(", "pi", "x", ")"]), "set_text splits multi-char keys, drops spaces")
	print("keybuffer_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
