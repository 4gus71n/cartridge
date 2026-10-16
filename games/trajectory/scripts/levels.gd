class_name Levels
extends RefCounted
## The 30 hand-designed levels. Plot is x, y ∈ [-10, 10].
##   form: stepper form (see Forms.SPECS) or "free" (keypad expression)
##   ideal: param values (stepper) or ASCII expression (free) that solves it
##   lock: params fixed for this level (shown greyed out)
##   preview: live curve preview while editing
##   intro: teaching blurb key shown the first time (INTRO_<key>_T / INTRO_<key>)
##   targets: [x, y] (the last one is drawn as a star)
##   rocks: [x, y, radius]   walls: [x0, y0, x1, y1]
##   keys: keypad extras for free levels ("trig")

const WORLDS := [
	{"key": "W_CONST", "count": 4},
	{"key": "W_LINEAR", "count": 7},
	{"key": "W_QUAD", "count": 7},
	{"key": "W_CUBIC", "count": 4},
	{"key": "W_FREE", "count": 5},
	{"key": "W_WAVES", "count": 3},
]

const LIST := [
	# --- World 1: constants y = c ------------------------------------------
	{"form": "c", "ideal": {"c": 3}, "preview": true, "intro": "CONST",
		"targets": [[-5, 3], [5, 3]], "rocks": [[0, -3, 1.0]]},
	{"form": "c", "ideal": {"c": -5}, "preview": true,
		"targets": [[-6, -5], [0, -5], [6, -5]], "rocks": [[-3, 0, 1.2], [3, 2, 0.9]]},
	{"form": "c", "ideal": {"c": 2}, "preview": true,
		"targets": [[-6, 2], [7, 2]], "walls": [[1, -10, 1.8, 0.6], [1, 3.4, 1.8, 10]]},
	{"form": "c", "ideal": {"c": -3}, "preview": false, "intro": "HIDDEN",
		"targets": [[-7, -3], [0, -3], [6, -3]], "rocks": [[-3.5, -0.5, 1.1], [3, -6, 1.2], [8, 1, 1.0]]},
	# --- World 2: lines ---------------------------------------------------
	{"form": "mx", "ideal": {"m": 1}, "preview": true, "intro": "SLOPE",
		"targets": [[2, 2], [6, 6]], "rocks": [[-5, 2, 1.1]]},
	{"form": "mx", "ideal": {"m": 2}, "preview": true,
		"targets": [[1, 2], [4, 8]], "rocks": [[3, 2, 1.0], [-2, 1, 1.0]]},
	{"form": "mx", "ideal": {"m": -0.5}, "preview": true,
		"targets": [[-8, 4], [6, -3]], "rocks": [[0, 3, 1.2], [4, 1, 1.0]]},
	{"form": "mxb", "lock": {"m": 1}, "ideal": {"m": 1, "b": 2}, "preview": true, "intro": "INTERCEPT",
		"targets": [[-5, -3], [0, 2], [3, 5]], "rocks": [[-2, 4, 1.1], [5, 3, 1.0]]},
	{"form": "mxb", "ideal": {"m": 0.5, "b": -2}, "preview": true,
		"targets": [[-6, -5], [4, 0], [8, 2]], "rocks": [[-3, -7, 1.1]], "walls": [[0, 0.5, 0.8, 10]]},
	{"form": "mxb", "ideal": {"m": -2, "b": 3}, "preview": false,
		"targets": [[0, 3], [2, -1], [4, -5]], "rocks": [[-2, 2, 1.1], [3, 1, 1.0]]},
	{"form": "mxb", "ideal": {"m": 1.5, "b": -4}, "preview": false,
		"targets": [[-2, -7], [2, -1], [6, 5]],
		"walls": [[0, -10, 0.6, -5.5], [3.6, -10, 4.2, 0], [3.6, 4, 4.2, 10]]},
	# --- World 3: parabolas -----------------------------------------------
	{"form": "vertex", "lock": {"a": 1}, "ideal": {"a": 1, "h": 2, "k": -3}, "preview": true, "intro": "VERTEX",
		"targets": [[0, 1], [2, -3], [4, 1]], "rocks": [[2, 3, 1.2]]},
	{"form": "vertex", "ideal": {"a": -1, "h": -1, "k": 6}, "preview": true, "intro": "STRETCH",
		"targets": [[-4, -3], [-1, 6], [2, -3]], "rocks": [[-1, 1, 1.2], [5, 6, 1.0]]},
	{"form": "vertex", "ideal": {"a": 0.25, "h": 0, "k": -6}, "preview": true,
		"targets": [[-4, -2], [0, -6], [6, 3]], "rocks": [[0, -1, 1.0], [-8, -4, 1.0]]},
	{"form": "vertex", "ideal": {"a": 2, "h": 3, "k": -8}, "preview": false,
		"targets": [[2, -6], [3, -8], [4, -6], [5, 0]], "rocks": [[0, -4, 1.0], [6.5, -5, 1.1]]},
	{"form": "std", "ideal": {"a": 1, "b": -2, "c": -3}, "preview": true, "intro": "STD",
		"targets": [[-1, 0], [0, -3], [1, -4], [3, 0]], "rocks": [[1, 0, 1.1], [-4, 3, 1.0]]},
	{"form": "roots2", "ideal": {"a": 0.5, "p": -4, "q": 2}, "preview": true, "intro": "ROOTS",
		"targets": [[-4, 0], [-1, -4.5], [2, 0], [4, 8]], "rocks": [[-1, 2, 1.2], [6, 2, 1.0]]},
	{"form": "roots2", "ideal": {"a": -0.5, "p": -3, "q": 5}, "preview": false,
		"targets": [[-3, 0], [1, 8], [5, 0]], "rocks": [[1, 4, 1.2], [-6, 4, 1.0], [8, -4, 1.0]]},
	# --- World 4: cubics --------------------------------------------------
	{"form": "roots3", "lock": {"a": 0.05}, "ideal": {"a": 0.05, "p": -6, "q": 0, "r": 6}, "preview": true,
		"intro": "CUBIC",
		"targets": [[-6, 0], [-3, 4.05], [0, 0], [3, -4.05], [6, 0]], "rocks": [[-3, -2, 1.1], [3, 2, 1.1]]},
	{"form": "roots3", "ideal": {"a": -0.1, "p": -5, "q": -1, "r": 4}, "preview": true,
		"targets": [[-5, 0], [-1, 0], [2, 4.2], [4, 0]], "rocks": [[-3, 1.5, 1.0], [0, -3, 1.0]]},
	{"form": "roots3", "ideal": {"a": 0.2, "p": -4, "q": 1, "r": 3}, "preview": false,
		"targets": [[-4, 0], [-2, 6], [2, -1.2], [4, 4.8]], "rocks": [[-6.5, -2, 1.0]],
		"walls": [[0, 4, 0.6, 10], [0, -10, 0.6, -2]]},
	{"form": "roots3", "ideal": {"a": -0.05, "p": -8, "q": -2, "r": 5}, "preview": false,
		"targets": [[-8, 0], [-5, -4.5], [0, 4], [2, 6], [5, 0]], "rocks": [[-2.5, 4.5, 1.0], [7.5, -2.5, 1.0]]},
	# --- World 5: free flight (keypad) -------------------------------------
	{"form": "free", "ideal": "2x+1", "preview": true, "intro": "KEYPAD",
		"targets": [[-3, -5], [0, 1], [4, 9]], "rocks": [[-4, 3, 1.1], [3, 2, 1.0]]},
	{"form": "free", "ideal": "x^2-4", "preview": true,
		"targets": [[-2, 0], [0, -4], [2, 0], [3, 5]], "rocks": [[0, 2, 1.2], [-5, -3, 1.0]]},
	{"form": "free", "ideal": "(x-1)^2/2-3", "preview": false,
		"targets": [[-3, 5], [1, -3], [5, 5]], "rocks": [[1, 1.5, 1.2]], "walls": [[-7, -10, -6.4, 4]]},
	{"form": "free", "ideal": "x(x-3)(x+3)/4", "preview": false,
		"targets": [[-3, 0], [-2, 2.5], [2, -2.5], [4, 7]], "rocks": [[0, 4, 1.2], [0, -4, 1.2]]},
	{"form": "free", "ideal": "0.5x^2-x-4", "preview": false,
		"targets": [[-2, 0], [1, -4.5], [4, 0], [6, 8]], "rocks": [[-4, -3, 1.2], [1, 0, 1.2]],
		"walls": [[1.5, -10, 2.1, -6.5]]},
	# --- World 6: waves ---------------------------------------------------
	{"form": "free", "ideal": "3sin(x)", "preview": true, "intro": "SINE", "keys": "trig",
		"targets": [[-4.712, 3], [-1.571, -3], [1.571, 3], [4.712, -3], [7.854, 3]],
		"rocks": [[-0.3, 3.5, 0.9], [3.14, -3.5, 0.9]]},
	{"form": "free", "ideal": "2sin(x)+4", "preview": false, "keys": "trig",
		"targets": [[-1.571, 2], [1.571, 6], [4.712, 2], [7.854, 6]], "rocks": [[0, 1, 1.0], [3.14, 7, 1.0]],
		"walls": [[-6, -10, -5.4, 0.5]]},
	{"form": "free", "ideal": "0.5x+2sin(x)", "preview": false, "keys": "trig",
		"targets": [[-4.712, -0.356], [-1.571, -2.785], [1.571, 2.785], [4.712, 0.356], [7.854, 5.927]],
		"rocks": [[-0.3, 3, 0.9], [3.14, -1, 0.9]]},
]


static func count() -> int:
	return LIST.size()


static func get_level(i: int) -> Dictionary:
	return LIST[i]


## World index of level i.
static func world_of(i: int) -> int:
	var acc := 0
	for w in WORLDS.size():
		acc += WORLDS[w].count
		if i < acc:
			return w
	return WORLDS.size() - 1


## First level index of world w.
static func world_start(w: int) -> int:
	var acc := 0
	for k in w:
		acc += WORLDS[k].count
	return acc


## The expression a level's ideal answer stands for.
static func ideal_expr(level: Dictionary) -> String:
	if level.form == "free":
		return level.ideal
	return Forms.expr(level.form, level.ideal)


## Display string of the ideal answer ("y = …").
static func ideal_pretty(level: Dictionary) -> String:
	if level.form == "free":
		return MathExpr.pretty(level.ideal)
	var v := {}
	for k in level.ideal:
		v[k] = float(level.ideal[k])
	return Forms.pretty(level.form, v)
