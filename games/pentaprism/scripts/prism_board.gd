class_name PrismBoard
extends RefCounted
## Pentaprism rules, independent of any scene (headless-testable).
##
## A 9x16 well. Pieces fall, are moved/rotated/held like any block-drop game,
## but on lock every gem drops straight down on its own (no holes ever) and
## then two things clear:
##   * any orthogonally connected group of MIN_GROUP+ gems of the same hue;
##   * any completely filled row ("prism line").
## Clears let gems above fall again, which can trigger more clears: a chain.
## The view drives resolution one step at a time so it can animate it.

enum State { PLAYING, RESOLVING, OVER }

const MIN_GROUP := 4
const LOCK_DELAY := 0.5
const MAX_LOCK_RESETS := 15
const CELLS_PER_LEVEL := 40
const MAX_LEVEL := 20
const PREVIEW := 3
const KICKS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(2, 0),
	Vector2i(-2, 0), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, -1),
]

var width := 9
var height := 16
var grid := PackedInt32Array() # hue per cell, 0 = empty; index = y * width + x
var state := State.PLAYING
var bag: Pieces.Bag
var current: Pieces.Piece
var queue: Array[Pieces.Piece] = []
var held: Pieces.Piece
var can_hold := true

var score := 0
var level := 1
var cleared_cells := 0
var rows_cleared := 0
var pieces_placed := 0
var chain := 0 # clear steps triggered by the piece being resolved
var combo := 0 # consecutive pieces that cleared something
var best_chain := 0

var _fall_timer := 0.0
var _lock_timer := 0.0
var _lock_resets := 0


func _init(w: int = 9, h: int = 16, seed_value: int = -1) -> void:
	width = w
	height = h
	grid.resize(w * h)
	grid.fill(0)
	bag = Pieces.Bag.new(seed_value)


func start() -> bool:
	while queue.size() < PREVIEW:
		queue.append(bag.next_piece())
	return spawn()


func index(x: int, y: int) -> int:
	return y * width + x


func at(x: int, y: int) -> int:
	return grid[y * width + x]


# --- active piece -------------------------------------------------------

## Takes the next queued piece (or `piece` when given, used by hold).
func spawn(piece: Pieces.Piece = null) -> bool:
	if piece == null:
		piece = queue.pop_front()
		queue.append(bag.next_piece())
	piece.pos = Vector2i(width / 2, -piece.min_y())
	current = piece
	_fall_timer = 0.0
	_lock_timer = 0.0
	_lock_resets = 0
	if collides(piece.cells, piece.pos):
		state = State.OVER
		return false
	state = State.PLAYING
	return true


func collides(cells: Array[Vector2i], pos: Vector2i) -> bool:
	for c in cells:
		var x := pos.x + c.x
		var y := pos.y + c.y
		if x < 0 or x >= width or y >= height:
			return true
		if y >= 0 and grid[y * width + x] != 0:
			return true
	return false


func move(dx: int) -> bool:
	if state != State.PLAYING:
		return false
	var p := current.pos + Vector2i(dx, 0)
	if collides(current.cells, p):
		return false
	current.pos = p
	_touch_lock()
	return true


func rotate(dir: int = 1) -> bool:
	if state != State.PLAYING:
		return false
	var cells := current.rotated_cells(dir)
	for k in KICKS:
		if not collides(cells, current.pos + k):
			current.cells = cells
			current.pos += k
			_touch_lock()
			return true
	return false


func grounded() -> bool:
	return collides(current.cells, current.pos + Vector2i(0, 1))


func soft_drop() -> bool:
	if state != State.PLAYING or grounded():
		return false
	current.pos.y += 1
	_fall_timer = 0.0
	score += 1
	return true


## Drops to the floor and locks. Returns the distance dropped.
func hard_drop() -> int:
	if state != State.PLAYING:
		return 0
	var d := ghost_y() - current.pos.y
	current.pos.y += d
	score += 2 * d
	lock()
	return d


func ghost_y() -> int:
	var y := current.pos.y
	while not collides(current.cells, Vector2i(current.pos.x, y + 1)):
		y += 1
	return y


func hold() -> bool:
	if state != State.PLAYING or not can_hold:
		return false
	# Reset orientation but keep this piece's hues on the same cells.
	var fresh := _unrotated(current)
	var out := held
	held = fresh
	can_hold = false
	if out == null:
		return spawn()
	return spawn(out)


## Same piece back in spawn orientation (colours follow their cells).
func _unrotated(p: Pieces.Piece) -> Pieces.Piece:
	var base := Pieces.base_cells(p.shape)
	var q := p.duplicate_piece()
	for turns in 4:
		if _same_cell_set(q.cells, base):
			# Reorder colours to the base cell order.
			var out := Pieces.Piece.new()
			out.shape = p.shape
			out.cells = base
			out.colors.resize(base.size())
			for i in base.size():
				out.colors[i] = q.colors[q.cells.find(base[i])]
			return out
		q.cells = q.rotated_cells(-1)
	return p.duplicate_piece()


func _same_cell_set(a: Array[Vector2i], b: Array[Vector2i]) -> bool:
	if a.size() != b.size():
		return false
	for c in a:
		if not b.has(c):
			return false
	return true


func fall_interval() -> float:
	return maxf(0.06, 0.85 * pow(0.86, level - 1))


## Gravity + lock delay. Returns true when the piece locked this frame.
func update(dt: float) -> bool:
	if state != State.PLAYING:
		return false
	if grounded():
		_lock_timer += dt
		if _lock_timer >= LOCK_DELAY:
			lock()
			return true
		return false
	_fall_timer += dt
	var interval := fall_interval()
	while _fall_timer >= interval:
		_fall_timer -= interval
		current.pos.y += 1
		if grounded():
			_fall_timer = 0.0
			break
	return false


func _touch_lock() -> void:
	if _lock_timer > 0.0 and _lock_resets < MAX_LOCK_RESETS:
		_lock_timer = 0.0
		_lock_resets += 1


# --- locking & resolution -------------------------------------------------

## Writes the piece into the grid and enters RESOLVING (or OVER on top-out).
func lock() -> void:
	var topped := false
	for i in current.cells.size():
		var x := current.pos.x + current.cells[i].x
		var y := current.pos.y + current.cells[i].y
		if y < 0:
			topped = true
			continue
		grid[y * width + x] = current.colors[i]
	pieces_placed += 1
	can_hold = true
	chain = 0
	current = null
	state = State.OVER if topped else State.RESOLVING


## Lets loose gems fall to the bottom of their column.
## Returns [[from_index, to_index], ...] for the gems that moved.
func settle() -> Array:
	var falls := []
	for x in width:
		var write := height - 1
		for y in range(height - 1, -1, -1):
			var v := grid[y * width + x]
			if v == 0:
				continue
			if write != y:
				grid[write * width + x] = v
				grid[y * width + x] = 0
				falls.append([y * width + x, write * width + x])
			write -= 1
	return falls


## Cells to clear right now: same-hue groups >= MIN_GROUP, plus full rows.
## Returns {"cells": {index: hue}, "groups": [[idx..]], "rows": [y..]}.
func find_clears() -> Dictionary:
	var cells := {}
	var groups := []
	var seen := PackedByteArray()
	seen.resize(grid.size())
	for start_i in grid.size():
		if grid[start_i] == 0 or seen[start_i]:
			continue
		var hue := grid[start_i]
		var group := [start_i]
		seen[start_i] = 1
		var k := 0
		while k < group.size():
			var i: int = group[k]
			k += 1
			var x := i % width
			var y := i / width
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or ny < 0 or nx >= width or ny >= height:
					continue
				var j := ny * width + nx
				if not seen[j] and grid[j] == hue:
					seen[j] = 1
					group.append(j)
		if group.size() >= MIN_GROUP:
			groups.append(group)
			for i in group:
				cells[i] = hue
	var rows := []
	for y in height:
		var full := true
		for x in width:
			if grid[y * width + x] == 0:
				full = false
				break
		if full:
			rows.append(y)
			for x in width:
				cells[y * width + x] = grid[y * width + x]
	return {"cells": cells, "groups": groups, "rows": rows}


## Points for one clear step (before it is applied).
func points_for(n_cells: int, n_rows: int, chain_step: int) -> int:
	return (n_cells * 10 + n_rows * 100) * chain_step * level


## One resolution step: settle, then clear whatever matches.
## Returns {"falls", "cells" (index->hue), "groups", "rows", "chain",
## "points", "done"}. When done is true nothing cleared; call finish().
func resolve_step() -> Dictionary:
	var falls := settle()
	var found := find_clears()
	var result := {
		"falls": falls, "cells": found.cells, "groups": found.groups,
		"rows": found.rows, "chain": chain, "points": 0, "done": true,
	}
	if found.cells.is_empty():
		return result
	chain += 1
	best_chain = maxi(best_chain, chain)
	var pts := points_for(found.cells.size(), found.rows.size(), chain)
	score += pts
	for i in found.cells:
		grid[i] = 0
	cleared_cells += found.cells.size()
	rows_cleared += found.rows.size()
	level = mini(MAX_LEVEL, 1 + cleared_cells / CELLS_PER_LEVEL)
	result.chain = chain
	result.points = pts
	result.done = false
	return result


## Ends resolution: combo bookkeeping + next piece. Returns the combo bonus
## awarded (0 if none). Sets state OVER when the next piece can't spawn.
func finish() -> int:
	var bonus := 0
	if chain > 0:
		combo += 1
		if combo > 1:
			bonus = 50 * (combo - 1) * level
			score += bonus
	else:
		combo = 0
	spawn()
	return bonus


## Resolves everything at once (tests and bots). Returns the steps.
func resolve_all() -> Array:
	var steps := []
	while true:
		var s := resolve_step()
		steps.append(s)
		if s.done:
			break
	finish()
	return steps


func filled() -> int:
	var n := 0
	for v in grid:
		if v != 0:
			n += 1
	return n
