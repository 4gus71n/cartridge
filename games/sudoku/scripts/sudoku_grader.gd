class_name SudokuGrader
extends RefCounted
## Human-style logical solver used to grade puzzles by the hardest technique
## they require:
##   EASY   (1) naked + hidden singles only
##   MEDIUM (2) + naked/hidden pairs, pointing pairs, box/line claiming
##   HARD   (3) + naked/hidden triples, X-wing, swordfish, XY-wing
##   EXPERT (4) needs something beyond that (chains, guessing…)
## Techniques are tried cheapest-first and the loop restarts after any
## progress, so a puzzle's grade is the minimum tier that cracks it.

enum { EASY = 1, MEDIUM = 2, HARD = 3, EXPERT = 4 }

const ALL := 0x3FE

var values := PackedInt32Array()
var cand := PackedInt32Array()
var used := {} # technique name -> times applied
var level := 0
var _pop: PackedInt32Array
var _units: Array
var _peers: Array


static func grade(puzzle: PackedInt32Array) -> int:
	return SudokuGrader.new(puzzle).run()


## {level, solved, techniques: {name: count}, values}
static func analyze(puzzle: PackedInt32Array) -> Dictionary:
	var g := SudokuGrader.new(puzzle)
	var lv := g.run()
	return {"level": lv, "solved": g.is_solved(), "techniques": g.used, "values": g.values}


func _init(puzzle: PackedInt32Array) -> void:
	_pop = SudokuGrid.POP
	_units = SudokuGrid.UNITS
	_peers = SudokuGrid.PEERS
	values = puzzle.duplicate()
	cand.resize(81)
	for i in 81:
		cand[i] = 0 if values[i] > 0 else ALL
	for i in 81:
		if values[i] > 0:
			for p in _peers[i]:
				cand[p] &= ~(1 << values[i])


func is_solved() -> bool:
	for v in values:
		if v == 0:
			return false
	return true


## Runs the logical solve and returns the grade (EASY..EXPERT).
func run() -> int:
	level = EASY
	while not is_solved():
		if _naked_single() or _hidden_single():
			continue
		if _naked_subset(2) or _hidden_subset(2) or _pointing() or _claiming():
			level = maxi(level, MEDIUM)
			continue
		if _naked_subset(3) or _hidden_subset(3) or _fish(2) or _fish(3) or _xy_wing():
			level = maxi(level, HARD)
			continue
		level = EXPERT
		return level
	return level


func _note(name: String) -> void:
	used[name] = used.get(name, 0) + 1


func _place(i: int, d: int) -> void:
	values[i] = d
	cand[i] = 0
	var bit := 1 << d
	for p in _peers[i]:
		cand[p] &= ~bit


# --- tier 1 ---------------------------------------------------------------

func _naked_single() -> bool:
	for i in 81:
		if values[i] == 0 and _pop[cand[i]] == 1:
			_place(i, SudokuGrid.first_digit(cand[i]))
			_note("naked_single")
			return true
	return false


func _hidden_single() -> bool:
	for u in _units:
		for d in range(1, 10):
			var bit := 1 << d
			var where := -1
			var n := 0
			for c in u:
				if cand[c] & bit:
					n += 1
					where = c
			if n == 1:
				_place(where, d)
				_note("hidden_single")
				return true
	return false


# --- tier 2/3: subsets ----------------------------------------------------

func _combos(n: int, k: int) -> Array:
	var out := []
	if k == 2:
		for a in n:
			for b in range(a + 1, n):
				out.append([a, b])
	elif k == 3:
		for a in n:
			for b in range(a + 1, n):
				for c in range(b + 1, n):
					out.append([a, b, c])
	return out


func _naked_subset(k: int) -> bool:
	for u in _units:
		var cells := []
		for c in u:
			if values[c] == 0:
				var n: int = _pop[cand[c]]
				if n >= 2 and n <= k:
					cells.append(c)
		if cells.size() < k:
			continue
		for combo in _combos(cells.size(), k):
			var union := 0
			var members := []
			for idx in combo:
				union |= cand[cells[idx]]
				members.append(cells[idx])
			if _pop[union] != k:
				continue
			var changed := false
			for c in u:
				if values[c] == 0 and not members.has(c) and cand[c] & union:
					cand[c] &= ~union
					changed = true
			if changed:
				_note("naked_pair" if k == 2 else "naked_triple")
				return true
	return false


func _hidden_subset(k: int) -> bool:
	for u in _units:
		# pos[d] = bitmask of positions (0..8) in the unit holding candidate d.
		var digits := []
		var pos := {}
		for d in range(1, 10):
			var m := 0
			for idx in 9:
				if cand[u[idx]] & (1 << d):
					m |= 1 << idx
			var n: int = _pop[m]
			if n >= 2 and n <= k:
				digits.append(d)
				pos[d] = m
		if digits.size() < k:
			continue
		for combo in _combos(digits.size(), k):
			var union := 0
			var keep := 0
			for idx in combo:
				union |= pos[digits[idx]]
				keep |= 1 << digits[idx]
			if _pop[union] != k:
				continue
			var changed := false
			for idx in 9:
				if union & (1 << idx):
					var c: int = u[idx]
					if cand[c] & ~keep:
						cand[c] &= keep
						changed = true
			if changed:
				_note("hidden_pair" if k == 2 else "hidden_triple")
				return true
	return false


# --- tier 2: intersections --------------------------------------------------

## Box -> line: a digit confined to one row/column inside a box.
func _pointing() -> bool:
	for b in 9:
		var box: PackedInt32Array = _units[18 + b]
		for d in range(1, 10):
			var bit := 1 << d
			var rows := 0
			var cols := 0
			var n := 0
			for c in box:
				if cand[c] & bit:
					rows |= 1 << (c / 9)
					cols |= 1 << (c % 9)
					n += 1
			if n < 2:
				continue
			var line := -1
			if _pop[rows] == 1:
				line = _bit_index(rows)
			elif _pop[cols] == 1:
				line = 9 + _bit_index(cols)
			if line < 0:
				continue
			var changed := false
			for c in _units[line]:
				if SudokuGrid.box(c) != b and cand[c] & bit:
					cand[c] &= ~bit
					changed = true
			if changed:
				_note("pointing")
				return true
	return false


## Line -> box: a digit confined to one box inside a row/column.
func _claiming() -> bool:
	for li in 18:
		var line: PackedInt32Array = _units[li]
		for d in range(1, 10):
			var bit := 1 << d
			var boxes := 0
			var n := 0
			for c in line:
				if cand[c] & bit:
					boxes |= 1 << SudokuGrid.box(c)
					n += 1
			if n < 2 or _pop[boxes] != 1:
				continue
			var b := _bit_index(boxes)
			var changed := false
			for c in _units[18 + b]:
				if not line.has(c) and cand[c] & bit:
					cand[c] &= ~bit
					changed = true
			if changed:
				_note("claiming")
				return true
	return false


# --- tier 3: fish + wings ---------------------------------------------------

## X-wing (size 2) / swordfish (size 3), row- and column-based.
func _fish(size: int) -> bool:
	for d in range(1, 10):
		var bit := 1 << d
		for orient in 2:
			var lines := []
			var masks := []
			for l in 9:
				var m := 0
				for k in 9:
					var c: int = l * 9 + k if orient == 0 else k * 9 + l
					if cand[c] & bit:
						m |= 1 << k
				var n: int = _pop[m]
				if n >= 2 and n <= size:
					lines.append(l)
					masks.append(m)
			if lines.size() < size:
				continue
			for combo in _combos(lines.size(), size):
				var union := 0
				var base := []
				for idx in combo:
					union |= masks[idx]
					base.append(lines[idx])
				if _pop[union] != size:
					continue
				var changed := false
				for l in 9:
					if base.has(l):
						continue
					for k in 9:
						if union & (1 << k):
							var c: int = l * 9 + k if orient == 0 else k * 9 + l
							if cand[c] & bit:
								cand[c] &= ~bit
								changed = true
				if changed:
					_note("x_wing" if size == 2 else "swordfish")
					return true
	return false


func _xy_wing() -> bool:
	for pivot in 81:
		var pm: int = cand[pivot]
		if values[pivot] != 0 or _pop[pm] != 2:
			continue
		var wings := []
		for p in _peers[pivot]:
			var m: int = cand[p]
			if values[p] == 0 and _pop[m] == 2 and m != pm and _pop[m & pm] == 1:
				wings.append(p)
		for a in wings:
			var am: int = cand[a]
			var z := am & ~pm
			var need := (pm & ~am) | z
			for b in wings:
				if b == a or cand[b] != need:
					continue
				var changed := false
				for c in 81:
					if c == a or c == b or c == pivot:
						continue
					if cand[c] & z and SudokuGrid.is_peer(c, a) and SudokuGrid.is_peer(c, b):
						cand[c] &= ~z
						changed = true
				if changed:
					_note("xy_wing")
					return true
	return false


func _bit_index(m: int) -> int:
	for k in 10:
		if m & (1 << k):
			return k
	return -1
