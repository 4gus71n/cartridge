class_name SudokuGrid
extends RefCounted
## Shared 9x9 geometry tables and helpers. Cells are indexed 0..80 row-major,
## digits are 1..9, 0 means empty. Candidate sets are bitmasks using bits 1..9.

const ALL := 0x3FE

## 27 units: rows 0..8, columns 9..17, boxes 18..26 (PackedInt32Array of 9 cells).
static var UNITS: Array = _build_units()
## 81 x PackedInt32Array of the 20 peers of each cell.
static var PEERS: Array = _build_peers()
## 81*81 lookup: 1 when the two cells see each other.
static var PEER_FLAG: PackedByteArray = _build_peer_flags()
## Population count for masks up to 10 bits.
static var POP: PackedInt32Array = _build_pop()


static func row(i: int) -> int:
	return i / 9


static func col(i: int) -> int:
	return i % 9


static func box(i: int) -> int:
	return (i / 27) * 3 + (i % 9) / 3


static func is_peer(a: int, b: int) -> bool:
	return PEER_FLAG[a * 81 + b] == 1


## Lowest digit present in a candidate mask (0 if empty).
static func first_digit(mask: int) -> int:
	for d in range(1, 10):
		if mask & (1 << d):
			return d
	return 0


static func parse(s: String) -> PackedInt32Array:
	var g := PackedInt32Array()
	g.resize(81)
	for i in mini(81, s.length()):
		var ch := s.unicode_at(i)
		g[i] = ch - 48 if ch >= 49 and ch <= 57 else 0
	return g


static func stringify(g: PackedInt32Array) -> String:
	var parts := PackedStringArray()
	for v in g:
		parts.append(str(v) if v > 0 else ".")
	return "".join(parts)


## True when no digit repeats in any row, column or box (empties ignored).
static func is_consistent(g: PackedInt32Array) -> bool:
	for u in UNITS:
		var seen := 0
		for c in u:
			var v: int = g[c]
			if v == 0:
				continue
			if seen & (1 << v):
				return false
			seen |= 1 << v
	return true


## True for a completely filled, rule-abiding grid.
static func is_solved_grid(g: PackedInt32Array) -> bool:
	if g.size() != 81:
		return false
	for v in g:
		if v < 1 or v > 9:
			return false
	return is_consistent(g)


static func count_givens(g: PackedInt32Array) -> int:
	var n := 0
	for v in g:
		if v > 0:
			n += 1
	return n


static func _build_units() -> Array:
	var u := []
	for r in 9:
		var cells := PackedInt32Array()
		for c in 9:
			cells.append(r * 9 + c)
		u.append(cells)
	for c in 9:
		var cells := PackedInt32Array()
		for r in 9:
			cells.append(r * 9 + c)
		u.append(cells)
	for b in 9:
		var cells := PackedInt32Array()
		var r0 := (b / 3) * 3
		var c0 := (b % 3) * 3
		for k in 9:
			cells.append((r0 + k / 3) * 9 + c0 + k % 3)
		u.append(cells)
	return u


static func _build_peers() -> Array:
	var all := []
	for i in 81:
		var p := PackedInt32Array()
		for j in 81:
			if j != i and (row(i) == row(j) or col(i) == col(j) or box(i) == box(j)):
				p.append(j)
		all.append(p)
	return all


static func _build_peer_flags() -> PackedByteArray:
	var f := PackedByteArray()
	f.resize(81 * 81)
	for i in 81:
		for j in 81:
			if j != i and (row(i) == row(j) or col(i) == col(j) or box(i) == box(j)):
				f[i * 81 + j] = 1
	return f


static func _build_pop() -> PackedInt32Array:
	var p := PackedInt32Array()
	p.resize(1024)
	for m in 1024:
		var n := 0
		var x := m
		while x:
			n += x & 1
			x >>= 1
		p[m] = n
	return p
