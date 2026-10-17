class_name LevelGen
extends RefCounted
## Deterministic floor generator. Work is split into small phases so the UI
## can spread it across frames (no threads on web): call step() until it
## returns true, or use LevelGen.generate() in tests.

const CAVE_DEPTHS := [4, 7, 10]
const BOSS_DEPTH := 12

var depth: int
var rng: RandomNumberGenerator
var lv := Level.new()
var rooms: Array = [] # Rect2i
var _phases: Array = []
var _phase := 0


func _init(p_depth: int, run_seed: int) -> void:
	depth = p_depth
	rng = Seeds.make_rng(run_seed, 1000 + depth * 7919)
	lv.depth = depth
	lv.cave = depth in CAVE_DEPTHS
	if lv.cave:
		_phases = [_cave_fill, _cave_smooth, _cave_smooth, _cave_smooth, _cave_smooth, _cave_keep_largest]
	else:
		_phases = [_rooms, _connect, _doors]
	_phases += [_stairs_and_traps, _monsters, _items]


static func generate(p_depth: int, run_seed: int) -> Level:
	var g := LevelGen.new(p_depth, run_seed)
	while not g.step():
		pass
	return g.lv


## Runs one phase; true when the level is complete.
func step() -> bool:
	if _phase < _phases.size():
		_phases[_phase].call()
		_phase += 1
	return _phase >= _phases.size()


# --- rooms & corridors ---------------------------------------------------

func _rooms() -> void:
	var target := rng.randi_range(7, 10)
	if depth == BOSS_DEPTH:
		var hall := Rect2i(9, 15, 18, 13)
		rooms.append(hall)
		_carve_room(hall)
		target = 6
	for attempt in 200:
		if rooms.size() >= target:
			break
		var w := rng.randi_range(4, 9)
		var h := rng.randi_range(4, 8)
		var r := Rect2i(rng.randi_range(1, Level.W - w - 1), rng.randi_range(1, Level.H - h - 1), w, h)
		var ok := true
		for o in rooms:
			if r.grow(2).intersects(o):
				ok = false
				break
		if ok:
			rooms.append(r)
			_carve_room(r)


func _carve_room(r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			lv.tiles[Level.idx(x, y)] = Level.FLOOR


func _center(r: Rect2i) -> Vector2i:
	return Vector2i(r.position.x + r.size.x / 2, r.position.y + r.size.y / 2)


func _connect() -> void:
	for i in range(1, rooms.size()):
		var best := 0
		var best_d := 1 << 30
		for j in i:
			var d := (_center(rooms[i]) - _center(rooms[j])).length_squared()
			if d < best_d:
				best_d = d
				best = j
		_corridor(_center(rooms[i]), _center(rooms[best]))
	for k in 2:
		var a := rng.randi_range(0, rooms.size() - 1)
		var b := rng.randi_range(0, rooms.size() - 1)
		if a != b:
			_corridor(_center(rooms[a]), _center(rooms[b]))


func _corridor(a: Vector2i, b: Vector2i) -> void:
	var corner := Vector2i(b.x, a.y) if rng.randf() < 0.5 else Vector2i(a.x, b.y)
	_line(a, corner)
	_line(corner, b)


func _line(a: Vector2i, b: Vector2i) -> void:
	var p := a
	var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	while true:
		var i := Level.idx(p.x, p.y)
		if lv.tiles[i] == Level.WALL:
			lv.tiles[i] = Level.CORRIDOR
		if p == b:
			break
		p += step


func _doors() -> void:
	for r in rooms:
		for x in range(r.position.x, r.end.x):
			_maybe_door(x, r.position.y - 1, true)
			_maybe_door(x, r.end.y, true)
		for y in range(r.position.y, r.end.y):
			_maybe_door(r.position.x - 1, y, false)
			_maybe_door(r.end.x, y, false)


func _maybe_door(x: int, y: int, horizontal_edge: bool) -> void:
	if lv.tile(x, y) != Level.CORRIDOR:
		return
	var walls_ok := (lv.tile(x - 1, y) == Level.WALL and lv.tile(x + 1, y) == Level.WALL) if horizontal_edge \
		else (lv.tile(x, y - 1) == Level.WALL and lv.tile(x, y + 1) == Level.WALL)
	if not walls_ok:
		return
	var r := rng.randf()
	if r < 0.5:
		lv.tiles[Level.idx(x, y)] = Level.DOOR
	elif r < 0.75:
		lv.tiles[Level.idx(x, y)] = Level.OPEN_DOOR


# --- caves ---------------------------------------------------------------

func _cave_fill() -> void:
	for y in Level.H:
		for x in Level.W:
			var border := x == 0 or y == 0 or x == Level.W - 1 or y == Level.H - 1
			lv.tiles[Level.idx(x, y)] = Level.WALL if border or rng.randf() < 0.44 else Level.FLOOR


func _cave_smooth() -> void:
	var next := lv.tiles.duplicate()
	for y in range(1, Level.H - 1):
		for x in range(1, Level.W - 1):
			var walls := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if lv.tiles[Level.idx(x + dx, y + dy)] == Level.WALL:
						walls += 1
			next[Level.idx(x, y)] = Level.WALL if walls >= 5 else Level.FLOOR
	lv.tiles = next


func _cave_keep_largest() -> void:
	for attempt in 6:
		var label := PackedInt32Array()
		label.resize(Level.W * Level.H)
		label.fill(-1)
		var best_label := -1
		var best_size := 0
		var next_label := 0
		for i in Level.W * Level.H:
			if lv.tiles[i] == Level.WALL or label[i] != -1:
				continue
			var size := _flood(label, i, next_label)
			if size > best_size:
				best_size = size
				best_label = next_label
			next_label += 1
		for i in Level.W * Level.H:
			if lv.tiles[i] != Level.WALL and label[i] != best_label:
				lv.tiles[i] = Level.WALL
		if best_size >= Level.W * Level.H * 0.3:
			return
		# Too cramped: refill and retry.
		_cave_fill()
		for k in 4:
			_cave_smooth()


func _flood(label: PackedInt32Array, from: int, id: int) -> int:
	var stack := PackedInt32Array([from])
	label[from] = id
	var size := 0
	while not stack.is_empty():
		var c := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		size += 1
		var cx := c % Level.W
		var cy := c / Level.W
		for d in Pathing.DIRS:
			var nx: int = cx + d.x
			var ny: int = cy + d.y
			if not Level.in_bounds(nx, ny):
				continue
			var n := ny * Level.W + nx
			if label[n] == -1 and lv.tiles[n] != Level.WALL:
				label[n] = id
				stack.append(n)
	return size


# --- stairs, traps, population --------------------------------------------

var _dist: PackedInt32Array


func _random_floor_in(r: Rect2i) -> Vector2i:
	return Vector2i(rng.randi_range(r.position.x, r.end.x - 1), rng.randi_range(r.position.y, r.end.y - 1))


func _stairs_and_traps() -> void:
	var cells := lv.floor_cells()
	if depth == BOSS_DEPTH:
		# Enter far from the hall.
		var far: Rect2i = rooms[rooms.size() - 1]
		var best_d := -1
		for r in rooms.slice(1):
			var d := (_center(r) - _center(rooms[0])).length_squared()
			if d > best_d:
				best_d = d
				far = r
		lv.start = _random_floor_in(far)
	elif rooms.size() > 0:
		lv.start = _random_floor_in(rooms[0])
	else:
		lv.start = cells[rng.randi_range(0, cells.size() - 1)]
	_dist = Pathing.distance_map(lv, lv.start.x, lv.start.y)
	if depth != BOSS_DEPTH:
		var cand := []
		for c in cells:
			if _dist[Level.idx(c.x, c.y)] > 0:
				cand.append(c)
		cand.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return _dist[Level.idx(a.x, a.y)] > _dist[Level.idx(b.x, b.y)])
		var top := maxi(1, cand.size() / 7)
		lv.stairs = cand[rng.randi_range(0, top - 1)]
		lv.tiles[Level.idx(lv.stairs.x, lv.stairs.y)] = Level.STAIRS
	lv.tiles[Level.idx(lv.start.x, lv.start.y)] = Level.UPSTAIRS
	if depth >= 2:
		var n := rng.randi_range(1, 2 + depth / 4)
		for k in n:
			var c: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
			var i := Level.idx(c.x, c.y)
			if lv.tiles[i] == Level.FLOOR and _dist[i] > 4 and not lv.traps.has(i):
				lv.traps[i] = {"t": Defs.TRAPS[rng.randi_range(0, Defs.TRAPS.size() - 1)], "f": false}


func _free_floor(min_dist: int) -> Vector2i:
	for attempt in 300:
		var x := rng.randi_range(1, Level.W - 2)
		var y := rng.randi_range(1, Level.H - 2)
		var i := Level.idx(x, y)
		if lv.tiles[i] != Level.FLOOR or _dist[i] < min_dist:
			continue
		if not lv.monster_at(x, y).is_empty():
			continue
		return Vector2i(x, y)
	return Vector2i(-1, -1)


func _pick_monster() -> String:
	var ids := Defs.monsters_for(depth)
	var total := 0
	for id in ids:
		total += 3 if depth - int(Defs.mon(id).d[0]) <= 2 else 2
	var r := rng.randi_range(1, total)
	for id in ids:
		r -= 3 if depth - int(Defs.mon(id).d[0]) <= 2 else 2
		if r <= 0:
			return id
	return ids[0]


func add_monster(type: String, at: Vector2i) -> Dictionary:
	var m := Spawn.monster(type, at.x, at.y, rng)
	var flags: Array = Defs.mon(type).flags
	m.aw = rng.randf() < (0.1 if "sleeps" in flags else 0.45)
	lv.monsters.append(m)
	return m


func _monsters() -> void:
	if depth == BOSS_DEPTH:
		var hall: Rect2i = rooms[0]
		var king := add_monster("king", _center(hall))
		king.aw = false
		for t in ["skeleton", "skeleton", "cultist", "wraith"]:
			var p := _near_free(_center(hall), 4)
			if p.x >= 0:
				add_monster(t, p).aw = false
	var n := 3 + depth / 2 + rng.randi_range(0, 2)
	var placed := 0
	while placed < n:
		var p := _free_floor(8)
		if p.x < 0:
			p = _free_floor(3)
		if p.x < 0:
			break
		var type := _pick_monster()
		var lead := add_monster(type, p)
		placed += 1
		if "pack" in Defs.mon(type).flags:
			for k in rng.randi_range(0 if depth <= 2 else 1, 2):
				var q := _near_free(p, 2)
				if q.x >= 0:
					add_monster(type, q).aw = lead.aw
					placed += 1


func _near_free(c: Vector2i, radius: int) -> Vector2i:
	for attempt in 30:
		var p := c + Vector2i(rng.randi_range(-radius, radius), rng.randi_range(-radius, radius))
		if lv.tile(p.x, p.y) == Level.FLOOR and lv.monster_at(p.x, p.y).is_empty() and p != lv.start:
			return p
	return Vector2i(-1, -1)


func _items() -> void:
	var n := rng.randi_range(5, 8)
	for k in n:
		_drop(Spawn.random_item(depth, rng))
	if depth % 2 == 1:
		_drop(Spawn.item("ration"))
	for k in rng.randi_range(3, 5):
		_drop(Spawn.item("gold", rng.randi_range(4, 12) + depth * rng.randi_range(2, 6)))


func _drop(it: Dictionary) -> void:
	var p := _free_floor(1)
	if p.x < 0:
		p = lv.start
	lv.items.append({"x": p.x, "y": p.y, "it": it, "s": false})
