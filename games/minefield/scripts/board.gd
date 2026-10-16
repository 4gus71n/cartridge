class_name MineBoard
extends RefCounted
## Pure Minefield rules: layout, reveal/flood, flags, chording, win/lose.
## No nodes, no rendering, so it can be tested headless.

enum State { READY, PLAYING, WON, LOST }

var width: int
var height: int
var mine_count: int
var state: State = State.READY
var mines := PackedByteArray()
var revealed := PackedByteArray()
var flagged := PackedByteArray()
var adjacent := PackedByteArray()
var revealed_count := 0
var flag_count := 0
var exploded := -1
var _neighbors: Array[PackedInt32Array] = []


func _init(w: int, h: int, m: int) -> void:
	width = w
	height = h
	mine_count = m
	var n := w * h
	mines.resize(n)
	revealed.resize(n)
	flagged.resize(n)
	adjacent.resize(n)
	_neighbors.resize(n)
	for i in n:
		var x := i % w
		var y := i / w
		var list := PackedInt32Array()
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue
				var nx: int = x + dx
				var ny: int = y + dy
				if nx >= 0 and ny >= 0 and nx < w and ny < h:
					list.append(ny * w + nx)
		_neighbors[i] = list


func size() -> int:
	return width * height


func index(x: int, y: int) -> int:
	return y * width + x


func neighbors(i: int) -> PackedInt32Array:
	return _neighbors[i]


func safe_total() -> int:
	return size() - mine_count


func mines_left() -> int:
	return mine_count - flag_count


## Places mines at exactly these cell indices and recomputes the numbers.
func place_mines(cells: PackedInt32Array) -> void:
	mines.fill(0)
	for c in cells:
		mines[c] = 1
	for i in size():
		var count := 0
		for nb in _neighbors[i]:
			count += mines[nb]
		adjacent[i] = count


## Builds a layout where `first` and its neighbours are safe. With `no_guess`
## it retries until MineSolver can clear the board by logic alone from
## `first`. Returns false if no such layout was found (the last one is kept).
func generate(first: int, rng: RandomNumberGenerator, no_guess := true, max_attempts := 600) -> bool:
	var excluded := {first: true}
	for nb in _neighbors[first]:
		excluded[nb] = true
	var pool := PackedInt32Array()
	for i in size():
		if not excluded.has(i):
			pool.append(i)
	var count := mini(mine_count, pool.size())
	mine_count = count
	for attempt in max_attempts:
		# Partial Fisher-Yates: the first `count` entries become mines.
		for k in count:
			var j := rng.randi_range(k, pool.size() - 1)
			var tmp := pool[k]
			pool[k] = pool[j]
			pool[j] = tmp
		place_mines(pool.slice(0, count))
		if not no_guess or MineSolver.solvable(self, first):
			state = State.PLAYING
			return true
	state = State.PLAYING
	return false


## Reveals a cell (flood-filling zeros). Returns the newly revealed cells in
## reveal order (useful for animation). Flagged cells are ignored.
func reveal(i: int) -> PackedInt32Array:
	var opened := PackedInt32Array()
	if state != State.PLAYING or revealed[i] or flagged[i]:
		return opened
	if mines[i]:
		revealed[i] = 1
		exploded = i
		state = State.LOST
		opened.append(i)
		return opened
	var queue := PackedInt32Array([i])
	revealed[i] = 1
	revealed_count += 1
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		opened.append(c)
		if adjacent[c] == 0:
			for nb in _neighbors[c]:
				if not revealed[nb] and not flagged[nb] and not mines[nb]:
					revealed[nb] = 1
					revealed_count += 1
					queue.append(nb)
	if revealed_count == safe_total():
		_win()
	return opened


func toggle_flag(i: int) -> bool:
	if state != State.PLAYING or revealed[i]:
		return false
	flagged[i] = 1 - flagged[i]
	flag_count += 1 if flagged[i] else -1
	return true


## Tapping a satisfied number reveals all of its unflagged neighbours.
func chord(i: int) -> PackedInt32Array:
	var opened := PackedInt32Array()
	if state != State.PLAYING or not revealed[i] or adjacent[i] == 0:
		return opened
	var flags := 0
	for nb in _neighbors[i]:
		flags += flagged[nb]
	if flags != adjacent[i]:
		return opened
	for nb in _neighbors[i]:
		if not revealed[nb] and not flagged[nb]:
			opened.append_array(reveal(nb))
			if state == State.LOST:
				break
	return opened


func can_chord(i: int) -> bool:
	if not revealed[i] or adjacent[i] == 0:
		return false
	for nb in _neighbors[i]:
		if not revealed[nb] and not flagged[nb]:
			return true
	return false


func _win() -> void:
	state = State.WON
	for c in size():
		if mines[c] and not flagged[c]:
			flagged[c] = 1
			flag_count += 1
