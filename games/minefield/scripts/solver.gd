class_name MineSolver
extends RefCounted
## Logic-only solver used to guarantee "no-guess" boards. It plays the board
## from `first` using only information a player would see:
##   1. trivial rules (a number's remaining mines are 0 / equal its unknowns)
##   2. subset rule between pairs of nearby numbers
##   3. global mine count (all remaining unknowns are mines / safe)
## If it can open every safe cell, no guessing is ever required.


static func solvable(board: MineBoard, first: int) -> bool:
	var n := board.size()
	var open := PackedByteArray()
	open.resize(n)
	var known_mine := PackedByteArray()
	known_mine.resize(n)
	var opened := [0]
	var mines_found := [0]
	if board.mines[first]:
		return false
	_open(board, first, open, opened)
	var safe_total := board.safe_total()

	while opened[0] < safe_total:
		var progress := false
		# Frontier: opened numbers that still touch unknown cells.
		var frontier := PackedInt32Array()
		var unknowns: Dictionary = {} # cell -> PackedInt32Array of unknown nbs
		var need: Dictionary = {} # cell -> remaining mines among unknowns
		for c in n:
			if not open[c] or board.adjacent[c] == 0:
				continue
			var u := PackedInt32Array()
			var m := int(board.adjacent[c])
			for nb in board.neighbors(c):
				if known_mine[nb]:
					m -= 1
				elif not open[nb]:
					u.append(nb)
			if u.is_empty():
				continue
			frontier.append(c)
			unknowns[c] = u
			need[c] = m

		# 1. Trivial rules.
		for c in frontier:
			var u: PackedInt32Array = unknowns[c]
			var m: int = need[c]
			if m == 0:
				for cell in u:
					if not open[cell] and not known_mine[cell]:
						_open(board, cell, open, opened)
						progress = true
			elif m == u.size():
				for cell in u:
					if not known_mine[cell]:
						known_mine[cell] = 1
						mines_found[0] += 1
						progress = true
		if progress:
			continue

		# 2. Subset rule: if A's unknowns are inside B's, the difference holds
		# exactly need[B] - need[A] mines.
		for a in frontier:
			var ua: PackedInt32Array = unknowns[a]
			var ax := a % board.width
			var ay := a / board.width
			for b in frontier:
				if a == b:
					continue
				var bx := b % board.width
				var by := b / board.width
				if absi(ax - bx) > 2 or absi(ay - by) > 2:
					continue
				var ub: PackedInt32Array = unknowns[b]
				if ua.size() >= ub.size():
					continue
				var subset := true
				for cell in ua:
					if not ub.has(cell):
						subset = false
						break
				if not subset:
					continue
				var diff := PackedInt32Array()
				for cell in ub:
					if not ua.has(cell):
						diff.append(cell)
				var dm: int = need[b] - need[a]
				if dm == 0:
					for cell in diff:
						if not open[cell] and not known_mine[cell]:
							_open(board, cell, open, opened)
							progress = true
				elif dm == diff.size():
					for cell in diff:
						if not known_mine[cell]:
							known_mine[cell] = 1
							mines_found[0] += 1
							progress = true
				if progress:
					break
			if progress:
				break
		if progress:
			continue

		# 3. Global count.
		var remaining: int = board.mine_count - mines_found[0]
		var unknown_cells := PackedInt32Array()
		for c in n:
			if not open[c] and not known_mine[c]:
				unknown_cells.append(c)
		if remaining == 0:
			for c in unknown_cells:
				if not open[c]:
					_open(board, c, open, opened)
			progress = true
		elif remaining == unknown_cells.size():
			for c in unknown_cells:
				known_mine[c] = 1
			mines_found[0] += remaining
			progress = true
		if not progress:
			return false
	return true


static func _open(board: MineBoard, start: int, open: PackedByteArray, opened: Array) -> void:
	if open[start]:
		return
	var queue := PackedInt32Array([start])
	open[start] = 1
	opened[0] += 1
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		if board.adjacent[c] == 0:
			for nb in board.neighbors(c):
				if not open[nb] and not board.mines[nb]:
					open[nb] = 1
					opened[0] += 1
					queue.append(nb)
