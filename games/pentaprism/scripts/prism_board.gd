class_name PrismBoard
extends RefCounted
## Pentaprism rules (v2 "stone rise"), independent of any scene (headless-testable).
##
## A 9x16 well. Pieces fall, move, rotate and hold like any block-drop game and
## lock RIGID where they land: overhangs leave holes. Then two things clear:
##   * any orthogonally connected group of MIN_GROUP+ gems of one hue
##     (a "penta match");
##   * any completely filled row, stones included (a "prism line").
## Only gems above a clear fall (column by column, into the opened gaps); that
## can trigger more clears: a chain. A STONE next to a clearing cell cracks into
## a random gem. Every `stone_interval()` locked pieces a stone row with 1-2
## gaps rises from the floor and pushes the stack up; topping out loses.
## The view drives resolution one step at a time so it can animate it.

enum State { PLAYING, RESOLVING, OVER }

const SAVE_VERSION := 2
const STONE := 9 # grid value of a stone block (never matches)
const MIN_GROUP := 5
const LOCK_DELAY := 0.5
const MAX_LOCK_RESETS := 15
const CELLS_PER_LEVEL := 40
const MAX_LEVEL := 20
const PREVIEW := 3
const STONE_START := 10 # pieces between stone rows at level 1
const STONE_MIN := 4 # ... never fewer than this
const STONE_LEVELS := 2 # levels per one-piece shrink of the stone interval
const START_STONE_ROWS := 2
const KICKS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(2, 0),
	Vector2i(-2, 0), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, -1),
]

var width := 9
var height := 16
var grid := PackedInt32Array() # 0 empty, 1..COLORS gem hue, STONE; index = y * width + x
var state := State.PLAYING
var bag: Pieces.Bag
var rng := RandomNumberGenerator.new() # stone gaps + cracked-gem hues
var current: Pieces.Piece
var queue: Array[Pieces.Piece] = []
var held: Pieces.Piece
var can_hold := true

# Tuning hooks (tools/sim.gd sweeps them; the game uses the defaults).
var min_group := MIN_GROUP
var stone_start := STONE_START
var stone_min := STONE_MIN
var stone_levels := STONE_LEVELS
var cells_per_level := CELLS_PER_LEVEL

var score := 0
var level := 1
var cleared_cells := 0
var rows_cleared := 0
var stones_cracked := 0
var pieces_placed := 0
var chain := 0 # clear steps triggered by the piece being resolved
var combo := 0 # consecutive pieces that cleared something
var best_chain := 0
var stones_in := STONE_START # locked pieces until the next stone row rises
var next_gaps := PackedInt32Array() # gap columns of the next stone row
var rose := false # finish() pushed a stone row up (view animates it)
var over_reason := "" # "spawn", "lock", "rise"

var _loose := {} # column -> lowest cleared y; gems above it fall next step
var _fall_timer := 0.0
var _lock_timer := 0.0
var _lock_resets := 0


func _init(w: int = 9, h: int = 16, seed_value: int = -1) -> void:
	width = w
	height = h
	grid.resize(w * h)
	grid.fill(0)
	bag = Pieces.Bag.new(seed_value)
	if seed_value < 0:
		rng.randomize()
	else:
		rng.seed = hash(seed_value * 7919 + 13)
	stones_in = stone_interval()
	next_gaps = _roll_gaps(PackedInt32Array())


## Deals the preview, raises the starting stone rows, spawns the first piece.
func start(stone_rows: int = START_STONE_ROWS) -> bool:
	for i in stone_rows:
		rise()
	while queue.size() < PREVIEW:
		queue.append(bag.next_piece())
	return spawn()


func index(x: int, y: int) -> int:
	return y * width + x


func at(x: int, y: int) -> int:
	return grid[y * width + x]


static func is_gem(v: int) -> bool:
	return v > 0 and v != STONE


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
		over_reason = "spawn"
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


## One row down. Placing pieces scores nothing: points come only from clears.
func soft_drop() -> bool:
	if state != State.PLAYING or grounded():
		return false
	current.pos.y += 1
	_fall_timer = 0.0
	return true


## Drops to the floor and locks. Returns the distance dropped.
func hard_drop() -> int:
	if state != State.PLAYING:
		return 0
	var d := ghost_y() - current.pos.y
	current.pos.y += d
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


## Pieces between stone rows: STONE_START at level 1, one fewer per level.
func stone_interval() -> int:
	return maxi(stone_min, stone_start - (level - 1) / stone_levels)


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

## Writes the piece into the grid exactly where it is (rigid: no per-gem
## drop) and enters RESOLVING, or OVER when part of it is above the well.
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
	_loose.clear()
	current = null
	if topped:
		state = State.OVER
		over_reason = "lock"
	else:
		state = State.RESOLVING


## Gems above the last clear fall down their column into the opened gaps.
## Cells below the lowest cleared cell of a column never move (old holes stay).
## Returns [[from_index, to_index], ...] for the cells that moved.
func settle() -> Array:
	var falls := []
	for x in _loose:
		var write: int = _loose[x]
		for y in range(write, -1, -1):
			var v := grid[y * width + x]
			if v == 0:
				continue
			if write != y:
				grid[write * width + x] = v
				grid[y * width + x] = 0
				falls.append([y * width + x, write * width + x])
			write -= 1
	_loose.clear()
	return falls


## Cells to clear right now: same-hue groups >= min_group, plus full rows.
## Returns {"cells": {index: value}, "groups": [[idx..]], "rows": [y..]}.
func find_clears() -> Dictionary:
	var cells := {}
	var groups := []
	var n := grid.size()
	var seen := PackedByteArray()
	seen.resize(n)
	var stack := PackedInt32Array()
	for start_i in n:
		var hue := grid[start_i]
		if hue == 0 or hue == STONE or seen[start_i]:
			continue
		seen[start_i] = 1
		var group := [start_i]
		stack.clear()
		stack.append(start_i)
		while not stack.is_empty():
			var i: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			var x := i % width
			if x > 0 and not seen[i - 1] and grid[i - 1] == hue:
				seen[i - 1] = 1
				stack.append(i - 1)
				group.append(i - 1)
			if x < width - 1 and not seen[i + 1] and grid[i + 1] == hue:
				seen[i + 1] = 1
				stack.append(i + 1)
				group.append(i + 1)
			if i >= width and not seen[i - width] and grid[i - width] == hue:
				seen[i - width] = 1
				stack.append(i - width)
				group.append(i - width)
			if i + width < n and not seen[i + width] and grid[i + width] == hue:
				seen[i + width] = 1
				stack.append(i + width)
				group.append(i + width)
		if group.size() >= min_group:
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


## One resolution step: drop gems into the last clear's gaps, then clear
## whatever matches and crack stones touching the cleared cells.
## Returns {"falls", "cells" (index->value), "groups", "rows", "cracks"
## (index->new hue), "chain", "points", "done"}. When done is true nothing
## cleared; call finish().
func resolve_step() -> Dictionary:
	var falls := settle()
	var found := find_clears()
	var result := {
		"falls": falls, "cells": found.cells, "groups": found.groups,
		"rows": found.rows, "cracks": {}, "chain": chain, "points": 0, "done": true,
	}
	if found.cells.is_empty():
		return result
	chain += 1
	best_chain = maxi(best_chain, chain)
	var pts := points_for(found.cells.size(), found.rows.size(), chain)
	score += pts
	var cracks := {}
	for i in found.cells:
		grid[i] = 0
		var x: int = i % width
		var y: int = i / width
		_loose[x] = maxi(_loose.get(x, -1), y)
	for i in found.cells:
		var x: int = i % width
		for j in [i - 1 if x > 0 else -1, i + 1 if x < width - 1 else -1, i - width, i + width]:
			if j >= 0 and j < grid.size() and grid[j] == STONE and not cracks.has(j):
				var hue := rng.randi_range(1, Pieces.palette)
				cracks[j] = hue
				grid[j] = hue
	stones_cracked += cracks.size()
	cleared_cells += found.cells.size()
	rows_cleared += found.rows.size()
	level = mini(MAX_LEVEL, 1 + cleared_cells / cells_per_level)
	result.cracks = cracks
	result.chain = chain
	result.points = pts
	result.done = false
	return result


## Ends resolution: combo bookkeeping, stone countdown (maybe a stone row
## rises: `rose`), next piece. Returns the combo bonus awarded (0 if none).
## Sets state OVER when the stack is pushed out or the next piece can't spawn.
func finish() -> int:
	var bonus := 0
	if chain > 0:
		combo += 1
		if combo > 1:
			bonus = 50 * (combo - 1) * level
			score += bonus
	else:
		combo = 0
	rose = false
	stones_in -= 1
	if stones_in <= 0:
		rose = true
		stones_in = stone_interval()
		if rise():
			state = State.OVER
			over_reason = "rise"
			current = null
			return bonus
	spawn()
	return bonus


## Pushes everything up one row and adds a stone row (gaps = next_gaps) at the
## floor. Returns true when gems were pushed out of the top (game over).
func rise() -> bool:
	var topped := false
	for x in width:
		if grid[x] != 0:
			topped = true
	for y in range(0, height - 1):
		for x in width:
			grid[y * width + x] = grid[(y + 1) * width + x]
	var base := (height - 1) * width
	for x in width:
		grid[base + x] = 0 if next_gaps.has(x) else STONE
	for x in _loose.keys():
		_loose[x] = maxi(0, _loose[x] - 1)
	next_gaps = _roll_gaps(next_gaps)
	return topped


## 1 or 2 gap columns; the first gap often lines up with the previous row's.
func _roll_gaps(prev: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	if not prev.is_empty() and rng.randf() < 0.5:
		out.append(prev[0])
	else:
		out.append(rng.randi_range(0, width - 1))
	if rng.randf() < 0.5:
		var g := rng.randi_range(0, width - 2)
		if g >= out[0]:
			g += 1
		out.append(g)
	return out


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


func stones() -> int:
	var n := 0
	for v in grid:
		if v == STONE:
			n += 1
	return n


## Cheap copy for bots to try a placement (grid, scoring, rng; shares the bag).
func sim_copy() -> PrismBoard:
	var b := PrismBoard.new(width, height, 0)
	b.grid = grid.duplicate()
	b.bag = bag
	b.rng.seed = rng.seed
	b.rng.state = rng.state
	b.min_group = min_group
	b.stone_start = stone_start
	b.stone_min = stone_min
	b.stone_levels = stone_levels
	b.cells_per_level = cells_per_level
	b.level = level
	b.score = score
	b.cleared_cells = cleared_cells
	b.combo = combo
	b.stones_in = stones_in
	b.next_gaps = next_gaps.duplicate()
	b.state = state
	return b


# --- save / resume ----------------------------------------------------------

## Snapshot of a run between pieces (state PLAYING), for CartridgeStore.
func to_dict() -> Dictionary:
	var q := []
	for p in queue:
		q.append(p.to_dict())
	return {
		"v": SAVE_VERSION, "w": width, "h": height, "grid": Array(grid),
		"score": score, "level": level, "cleared": cleared_cells, "rows": rows_cleared,
		"cracked": stones_cracked, "placed": pieces_placed, "combo": combo,
		"best_chain": best_chain, "stones_in": stones_in, "next_gaps": Array(next_gaps),
		"rng_seed": rng.seed, "rng_state": rng.state, "bag": bag.to_dict(),
		"current": current.to_dict() if current != null else null,
		"held": held.to_dict() if held != null else null,
		"can_hold": can_hold, "queue": q,
	}


## Rebuilds a saved run; null when the data is missing, old or corrupt.
static func from_dict(d: Variant) -> PrismBoard:
	if not (d is Dictionary) or int(d.get("v", 0)) != SAVE_VERSION:
		return null
	var w := int(d.get("w", 0))
	var h := int(d.get("h", 0))
	var g: Variant = d.get("grid", [])
	if w < 3 or h < 6 or not (g is Array) or g.size() != w * h:
		return null
	var b := PrismBoard.new(w, h, 0)
	for i in g.size():
		var v := int(g[i])
		b.grid[i] = v if (v == STONE or (v >= 0 and v <= Pieces.COLORS)) else 0
	b.score = maxi(0, int(d.get("score", 0)))
	b.level = clampi(int(d.get("level", 1)), 1, MAX_LEVEL)
	b.cleared_cells = int(d.get("cleared", 0))
	b.rows_cleared = int(d.get("rows", 0))
	b.stones_cracked = int(d.get("cracked", 0))
	b.pieces_placed = int(d.get("placed", 0))
	b.combo = int(d.get("combo", 0))
	b.best_chain = int(d.get("best_chain", 0))
	b.stones_in = clampi(int(d.get("stones_in", STONE_START)), 1, STONE_START)
	b.next_gaps = PackedInt32Array()
	for x in d.get("next_gaps", []):
		b.next_gaps.append(clampi(int(x), 0, w - 1))
	if b.next_gaps.is_empty():
		b.next_gaps.append(0)
	b.rng.seed = int(d.get("rng_seed", 0))
	b.rng.state = int(d.get("rng_state", 0))
	if d.get("bag") is Dictionary:
		b.bag.from_dict(d.bag)
	b.held = Pieces.Piece.from_dict(d.get("held"))
	b.can_hold = bool(d.get("can_hold", true))
	for qd in d.get("queue", []):
		var p := Pieces.Piece.from_dict(qd)
		if p != null:
			b.queue.append(p)
	while b.queue.size() < PREVIEW:
		b.queue.append(b.bag.next_piece())
	var cur := Pieces.Piece.from_dict(d.get("current"))
	if cur == null:
		cur = b.queue.pop_front()
		b.queue.append(b.bag.next_piece())
	b.spawn(cur)
	return b
