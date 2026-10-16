class_name Forms
extends RefCounted
## Equation "forms" used by the coefficient-stepper levels: which parameters
## exist, their default ranges, how to turn values into a parseable
## expression and how to display them nicely (y = 0.5(x − 2)² + 3).

## form -> [[name, min, max, step, init], ...]
const SPECS := {
	"c": [["c", -9.0, 9.0, 1.0, 0.0]],
	"mx": [["m", -5.0, 5.0, 0.5, 0.0]],
	"mxb": [["m", -5.0, 5.0, 0.5, 0.0], ["b", -9.0, 9.0, 1.0, 0.0]],
	"vertex": [["a", -3.0, 3.0, 0.25, 1.0], ["h", -9.0, 9.0, 1.0, 0.0], ["k", -9.0, 9.0, 1.0, 0.0]],
	"std": [["a", -3.0, 3.0, 0.25, 1.0], ["b", -9.0, 9.0, 1.0, 0.0], ["c", -9.0, 9.0, 1.0, 0.0]],
	"roots2": [["a", -3.0, 3.0, 0.25, 1.0], ["p", -9.0, 9.0, 1.0, 0.0], ["q", -9.0, 9.0, 1.0, 0.0]],
	"roots3": [["a", -1.0, 1.0, 0.05, 0.1], ["p", -9.0, 9.0, 1.0, 0.0], ["q", -9.0, 9.0, 1.0, 0.0],
		["r", -9.0, 9.0, 1.0, 0.0]],
}

## Template shown in the teaching blurbs / HUD ("y = a(x − h)² + k").
const TEMPLATES := {
	"c": "y = c",
	"mx": "y = mx",
	"mxb": "y = mx + b",
	"vertex": "y = a(x − h)² + k",
	"std": "y = ax² + bx + c",
	"roots2": "y = a(x − p)(x − q)",
	"roots3": "y = a(x − p)(x − q)(x − r)",
	"free": "y = …",
}

const MINUS := "−"


## Parameter specs for a level (form defaults + per-level locks/inits).
## Returns [{name, min, max, step, init, locked}].
static func params_for(level: Dictionary) -> Array:
	var out := []
	var locks: Dictionary = level.get("lock", {})
	for s in SPECS.get(level.form, []):
		var p := {"name": s[0], "min": s[1], "max": s[2], "step": s[3], "init": s[4], "locked": false}
		if locks.has(s[0]):
			p.init = float(locks[s[0]])
			p.locked = true
		out.append(p)
	return out


static func initial_values(level: Dictionary) -> Dictionary:
	var v := {}
	for p in params_for(level):
		v[p.name] = p.init
	return v


## Parseable ASCII expression for the stepper values.
static func expr(form: String, v: Dictionary) -> String:
	var n := func(k: String) -> String: return "(%s)" % num(float(v.get(k, 0.0)))
	match form:
		"c":
			return n.call("c")
		"mx":
			return "%s*x" % n.call("m")
		"mxb":
			return "%s*x+%s" % [n.call("m"), n.call("b")]
		"vertex":
			return "%s*(x-%s)^2+%s" % [n.call("a"), n.call("h"), n.call("k")]
		"std":
			return "%s*x^2+%s*x+%s" % [n.call("a"), n.call("b"), n.call("c")]
		"roots2":
			return "%s*(x-%s)*(x-%s)" % [n.call("a"), n.call("p"), n.call("q")]
		"roots3":
			return "%s*(x-%s)*(x-%s)*(x-%s)" % [n.call("a"), n.call("p"), n.call("q"), n.call("r")]
	return "0"


## Human form ("2x − 3"). `colors` maps param name -> hex colour to wrap the
## values in BBCode (for the in-game equation); empty = plain text.
static func pretty(form: String, v: Dictionary, colors := {}) -> String:
	var c := func(k: String, text: String) -> String:
		return "[color=%s]%s[/color]" % [colors[k], text] if colors.has(k) else text
	var g := func(k: String) -> float: return float(v.get(k, 0.0))
	match form:
		"c":
			return c.call("c", num_signed(g.call("c")))
		"mx":
			return _sum([_coef_term(g.call("m"), "x", "m", c)])
		"mxb":
			return _sum([_coef_term(g.call("m"), "x", "m", c), _const_term(g.call("b"), "b", c)])
		"std":
			return _sum([_coef_term(g.call("a"), "x²", "a", c), _coef_term(g.call("b"), "x", "b", c),
				_const_term(g.call("c"), "c", c)])
		"vertex":
			if is_zero_approx(g.call("a")):
				return _sum(["", _const_term(g.call("k"), "k", c)])
			var body := "x²" if is_zero_approx(g.call("h")) else "(x %s)²" % _shift(g.call("h"), "h", c)
			return _sum([_coef_term(g.call("a"), body, "a", c), _const_term(g.call("k"), "k", c)])
		"roots2", "roots3":
			if is_zero_approx(g.call("a")):
				return c.call("a", "0")
			var keys := ["p", "q"] if form == "roots2" else ["p", "q", "r"]
			# "x(x − 1)" reads better than "(x − 1)x": bare x factors go first.
			var bare := ""
			var shifted := ""
			for k in keys:
				if is_zero_approx(g.call(k)):
					bare += "x"
				else:
					shifted += "(x %s)" % _shift(g.call(k), k, c)
			bare = {"": "", "x": "x", "xx": "x²", "xxx": "x³"}[bare]
			return _coef_term(g.call("a"), bare + shifted, "a", c)
	return ""


## "−2x", "x", "0.5x²"; "" when the coefficient is 0.
static func _coef_term(k: float, body: String, key: String, c: Callable) -> String:
	if is_zero_approx(k):
		return ""
	var s := num_signed(k)
	if is_equal_approx(k, 1.0):
		s = ""
	elif is_equal_approx(k, -1.0):
		s = MINUS
	if s != "":
		s = c.call(key, s)
	return s + body


static func _const_term(k: float, key: String, c: Callable) -> String:
	if is_zero_approx(k):
		return ""
	return c.call(key, num_signed(k))


## "− 3" / "+ 3" for (x − h) style factors.
static func _shift(h: float, key: String, c: Callable) -> String:
	return ("%s %s" % [MINUS, c.call(key, num(h))]) if h > 0 else ("+ %s" % c.call(key, num(-h)))


## Joins terms with spaced signs: ["2x", "−3"] -> "2x − 3".
static func _sum(terms: Array) -> String:
	var out := ""
	for t in terms:
		if t == "":
			continue
		var neg := _visible(t).begins_with(MINUS)
		if out == "":
			out = t
		elif neg:
			out += " %s %s" % [MINUS, _strip_minus(t)]
		else:
			out += " + " + t
	return out if out != "" else "0"


## Text with a leading [color=..] tag skipped (to inspect the first glyph).
static func _visible(t: String) -> String:
	return t.substr(t.find("]") + 1) if t.begins_with("[color") else t


static func _strip_minus(t: String) -> String:
	if t.begins_with(MINUS):
		return t.substr(1)
	var i := t.find("]") + 1
	return t.substr(0, i) + t.substr(i + 1)


## Compact number: 3, 0.5, 0.25, 0.05 (no trailing zeros, no "-0").
static func num(v: float) -> String:
	if absf(v - roundf(v)) < 1e-9:
		var r := int(roundf(v))
		return str(r)
	var s := String.num(v, 4)
	if s.contains("."):
		s = s.rstrip("0").rstrip(".")
	return "0" if s == "-0" else s


## Like num() but with the typographic minus sign.
static func num_signed(v: float) -> String:
	var s := num(v)
	return MINUS + s.substr(1) if s.begins_with("-") else s
