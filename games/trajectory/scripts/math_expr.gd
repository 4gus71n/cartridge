class_name MathExpr
extends RefCounted
## Tiny expression parser/evaluator for y = f(x).
##
## Godot's Expression class uses pow() and has no implicit multiplication, so
## Trajectory ships its own recursive-descent parser that compiles to a flat
## RPN program (fast to evaluate thousands of times per frame).
##
## Grammar (lowest to highest precedence):
##   expr    := term (('+' | '-') term)*
##   term    := unary (('*' | '/') unary | <implicit> power)*
##   unary   := ('-' | '+') unary | power
##   power   := primary ('^' unary)?          # right-associative, -x^2 = -(x^2)
##   primary := number | 'x' | 'pi' | fn '(' expr ')' | '(' expr ')'
##   fn      := 'sin' | 'cos'
## Implicit multiplication: a factor followed by x, pi, '(' or a function
## (2x, 3(x+1), x(x-2), 2sin(x), (x+1)(x-1)). A number may not follow another
## factor implicitly (x2 is an error) because that is ambiguous.

enum { OP_NUM, OP_X, OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_POW, OP_NEG, OP_SIN, OP_COS }
enum { T_NUM, T_X, T_PI, T_OP, T_LP, T_RP, T_FN, T_END }

var ok := false
var error := ""        ## i18n key of the first error ("" when ok)
var error_pos := -1    ## character index of the offending token
var source := ""

var _ops := PackedInt32Array()
var _nums := PackedFloat64Array()
var _depth := 0
var _tokens: Array = []  # [type, value, pos]
var _i := 0


## Parses `text`. With `auto_close`, missing trailing ')' are appended first
## (the keypad lets players omit them).
static func parse(text: String, auto_close := false) -> MathExpr:
	var e := MathExpr.new()
	var src := text
	if auto_close:
		src += ")".repeat(maxi(0, open_parens(text)))
	e.source = src
	e._compile(src)
	return e


## Number of '(' not yet closed (counting function calls).
static func open_parens(text: String) -> int:
	var n := 0
	for ch in text:
		if ch == "(":
			n += 1
		elif ch == ")":
			n -= 1
	return n


func eval(x: float) -> float:
	if not ok:
		return NAN
	var st := PackedFloat64Array()
	st.resize(_depth + 1)
	var sp := -1
	for k in _ops.size():
		match _ops[k]:
			OP_NUM:
				sp += 1
				st[sp] = _nums[k]
			OP_X:
				sp += 1
				st[sp] = x
			OP_ADD:
				st[sp - 1] = st[sp - 1] + st[sp]
				sp -= 1
			OP_SUB:
				st[sp - 1] = st[sp - 1] - st[sp]
				sp -= 1
			OP_MUL:
				st[sp - 1] = st[sp - 1] * st[sp]
				sp -= 1
			OP_DIV:
				var d := st[sp]
				st[sp - 1] = st[sp - 1] / d if d != 0.0 else (NAN if st[sp - 1] == 0.0 else INF)
				sp -= 1
			OP_POW:
				st[sp - 1] = pow(st[sp - 1], st[sp])
				sp -= 1
			OP_NEG:
				st[sp] = -st[sp]
			OP_SIN:
				st[sp] = sin(st[sp])
			OP_COS:
				st[sp] = cos(st[sp])
	return st[0]


# --- tokenizer ------------------------------------------------------------

func _tokenize(src: String) -> bool:
	_tokens.clear()
	var i := 0
	var n := src.length()
	while i < n:
		var ch := src[i]
		if ch == " ":
			i += 1
		elif ch.is_valid_int() or ch == ".":
			var start := i
			var dots := 0
			while i < n and (src[i].is_valid_int() or src[i] == "."):
				if src[i] == ".":
					dots += 1
				i += 1
			var s := src.substr(start, i - start)
			if dots > 1 or s == ".":
				return _fail("ERR_NUMBER", start)
			_tokens.append([T_NUM, s.to_float(), start])
		elif ch == "x" or ch == "X":
			_tokens.append([T_X, 0, i])
			i += 1
		elif ch == "π":
			_tokens.append([T_PI, 0, i])
			i += 1
		elif src.substr(i, 2).to_lower() == "pi":
			_tokens.append([T_PI, 0, i])
			i += 2
		elif src.substr(i, 3).to_lower() in ["sin", "cos"]:
			_tokens.append([T_FN, src.substr(i, 3).to_lower(), i])
			i += 3
		elif ch in ["+", "-", "−", "*", "×", "·", "/", "÷", "^"]:
			var op: String = {"−": "-", "×": "*", "·": "*", "÷": "/"}.get(ch, ch)
			_tokens.append([T_OP, op, i])
			i += 1
		elif ch == "(":
			_tokens.append([T_LP, 0, i])
			i += 1
		elif ch == ")":
			_tokens.append([T_RP, 0, i])
			i += 1
		else:
			return _fail("ERR_CHAR", i)
	_tokens.append([T_END, 0, n])
	return true


# --- parser ---------------------------------------------------------------

func _compile(src: String) -> void:
	ok = false
	error = ""
	_ops.clear()
	_nums.clear()
	if src.strip_edges() == "":
		_fail("ERR_EMPTY", 0)
		return
	if not _tokenize(src):
		return
	_i = 0
	if not _expr():
		return
	if _peek()[0] != T_END:
		var t: Array = _peek()
		_fail("ERR_PAREN_CLOSE" if t[0] == T_RP else "ERR_UNEXPECTED", t[2])
		return
	_depth = _max_depth()
	ok = true


func _peek() -> Array:
	return _tokens[_i]


func _is_op(op: String) -> bool:
	var t: Array = _tokens[_i]
	return t[0] == T_OP and t[1] == op


func _expr() -> bool:
	if not _term():
		return false
	while _is_op("+") or _is_op("-"):
		var op: String = _peek()[1]
		_i += 1
		if not _term():
			return false
		_emit(OP_ADD if op == "+" else OP_SUB)
	return true


func _term() -> bool:
	if not _unary():
		return false
	while true:
		if _is_op("*") or _is_op("/"):
			var op: String = _peek()[1]
			_i += 1
			if not _unary():
				return false
			_emit(OP_MUL if op == "*" else OP_DIV)
		elif _peek()[0] in [T_X, T_PI, T_LP, T_FN]:
			if not _power():
				return false
			_emit(OP_MUL)
		elif _peek()[0] == T_NUM:
			return _fail("ERR_UNEXPECTED", _peek()[2])
		else:
			break
	return true


func _unary() -> bool:
	if _is_op("-"):
		_i += 1
		if not _unary():
			return false
		_emit(OP_NEG)
		return true
	if _is_op("+"):
		_i += 1
		return _unary()
	return _power()


func _power() -> bool:
	if not _primary():
		return false
	if _is_op("^"):
		_i += 1
		if not _unary():
			return false
		_emit(OP_POW)
	return true


func _primary() -> bool:
	var t: Array = _peek()
	match t[0]:
		T_NUM:
			_i += 1
			_emit(OP_NUM, t[1])
			return true
		T_X:
			_i += 1
			_emit(OP_X)
			return true
		T_PI:
			_i += 1
			_emit(OP_NUM, PI)
			return true
		T_FN:
			_i += 1
			if _peek()[0] != T_LP:
				return _fail("ERR_FN_PAREN", t[2])
			_i += 1
			if not _expr():
				return false
			if _peek()[0] != T_RP:
				return _fail("ERR_PAREN", _peek()[2])
			_i += 1
			_emit(OP_SIN if t[1] == "sin" else OP_COS)
			return true
		T_LP:
			_i += 1
			if not _expr():
				return false
			if _peek()[0] != T_RP:
				return _fail("ERR_PAREN", _peek()[2])
			_i += 1
			return true
		T_END:
			return _fail("ERR_INCOMPLETE", t[2])
	return _fail("ERR_UNEXPECTED", t[2])


func _emit(op: int, value := 0.0) -> void:
	_ops.append(op)
	_nums.append(value)


func _fail(key: String, pos: int) -> bool:
	if error == "":
		error = key
		error_pos = pos
	ok = false
	return false


func _max_depth() -> int:
	var d := 0
	var best := 0
	for op in _ops:
		if op == OP_NUM or op == OP_X:
			d += 1
		elif op in [OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_POW]:
			d -= 1
		best = maxi(best, d)
	return best


# --- display ----------------------------------------------------------------

## Pretty form of an ASCII expression for display: real minus sign, · for *,
## π, and ² / ³ superscripts for the common exponents.
static func pretty(text: String) -> String:
	var s := text.replace("pi", "π").replace("*", "·").replace("-", "−")
	var out := ""
	var i := 0
	while i < s.length():
		if s[i] == "^" and i + 1 < s.length() and (s[i + 1] == "2" or s[i + 1] == "3") \
				and (i + 2 >= s.length() or not (s[i + 2].is_valid_int() or s[i + 2] == ".")):
			out += "²" if s[i + 1] == "2" else "³"
			i += 2
			continue
		out += s[i]
		i += 1
	return out
