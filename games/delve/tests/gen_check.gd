extends SceneTree
## Generator, FOV, pathing and seed hashing checks.
## godot --headless --path . --script tests/gen_check.gd

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	_seeds()
	_levels()
	_fov()
	_pathing()
	print("gen_check: %d passed, %d failed (%d ms)" % [_pass, _fail, Time.get_ticks_msec() - t0])
	quit(1 if _fail > 0 else 0)


func _seeds() -> void:
	check(Seeds.hash32(1) != Seeds.hash32(2), "hash32 differs for 1/2")
	check(Seeds.hash32(12345) == Seeds.hash32(12345), "hash32 deterministic")
	var a := Seeds.make_rng(1, 5).randi()
	var b := Seeds.make_rng(2, 5).randi()
	check(a != b, "adjacent seeds give different streams")
	check(Seeds.make_rng(9, 5).randi() == Seeds.make_rng(9, 5).randi(), "make_rng deterministic")
	check(Seeds.code(123456).length() == 6, "seed code has 6 chars")
	var bits := 0
	for i in 64:
		bits += 1 if (Seeds.hash32(i) >> 31) & 1 == 1 else 0
	check(bits > 16 and bits < 48, "hash32 top bit balanced (%d/64)" % bits)


func _levels() -> void:
	var seeds := 40
	var bad := 0
	var caves := 0
	var stats_mon := 0
	for s in seeds:
		var run_seed := Seeds.hash32(s * 977 + 3)
		for depth in range(1, Defs.DEPTHS + 1):
			var lv := LevelGen.generate(depth, run_seed)
			if lv.cave:
				caves += 1
			var dist := Pathing.distance_map(lv, lv.start.x, lv.start.y)
			var ok := lv.tile(lv.start.x, lv.start.y) == Level.UPSTAIRS
			if depth < LevelGen.BOSS_DEPTH:
				ok = ok and lv.tile(lv.stairs.x, lv.stairs.y) == Level.STAIRS
				ok = ok and dist[Level.idx(lv.stairs.x, lv.stairs.y)] > 0
			else:
				var king := false
				for m in lv.monsters:
					if m.t == "king":
						king = true
						ok = ok and dist[Level.idx(m.x, m.y)] > 0
				ok = ok and king and lv.stairs == Vector2i(-1, -1)
			for m in lv.monsters:
				ok = ok and lv.passable(m.x, m.y) and Vector2i(m.x, m.y) != lv.start
				stats_mon += 1
			for e in lv.items:
				ok = ok and dist[Level.idx(e.x, e.y)] >= 0
			# Border is solid so nothing walks off the map.
			for x in Level.W:
				ok = ok and lv.tile(x, 0) == Level.WALL and lv.tile(x, Level.H - 1) == Level.WALL
			if not ok:
				bad += 1
				printerr("bad level seed=%d depth=%d" % [run_seed, depth])
	check(bad == 0, "stairs/king reachable and placements valid on %d seeds x 12 floors (%d bad)" % [seeds, bad])
	check(caves == seeds * LevelGen.CAVE_DEPTHS.size(), "cave floors at depths 4/7/10")
	check(stats_mon > seeds * 12 * 4, "floors are populated (%d monsters)" % stats_mon)
	var a := LevelGen.generate(3, 777)
	var b := LevelGen.generate(3, 777)
	var c := LevelGen.generate(3, 778)
	check(a.tiles == b.tiles and a.monsters.size() == b.monsters.size(), "generation deterministic per seed")
	check(a.tiles != c.tiles, "different seeds give different floors")
	# Deeper floors spawn deeper monsters.
	var deep := LevelGen.generate(11, 99)
	var shallow_only := true
	for m in deep.monsters:
		if int(Defs.mon(m.t).d[1]) < 11 and m.t != "king":
			shallow_only = false
	check(shallow_only, "depth-11 floor has only depth-appropriate monsters")
	check(Defs.monsters_for(1).size() >= 3 and Defs.monsters_for(12).size() >= 4, "monster roster scales by depth")
	check(Defs.MONSTERS.size() >= 15, "at least 15 monster types (%d)" % Defs.MONSTERS.size())


func _open_level() -> Level:
	var lv := Level.new()
	for y in range(1, Level.H - 1):
		for x in range(1, Level.W - 1):
			lv.tiles[Level.idx(x, y)] = Level.FLOOR
	return lv


func _fov() -> void:
	var lv := _open_level()
	var vis := Fov.compute(lv, 10, 10, 5)
	check(vis[Level.idx(10, 10)] == 1, "origin visible")
	check(vis[Level.idx(15, 10)] == 1 and vis[Level.idx(10, 5)] == 1, "radius edge visible")
	check(vis[Level.idx(17, 10)] == 0, "beyond radius not visible")
	var sym := true
	for d in [Vector2i(3, 1), Vector2i(-2, 3), Vector2i(-3, -3), Vector2i(1, -4)]:
		sym = sym and vis[Level.idx(10 + d.x, 10 + d.y)] == vis[Level.idx(10 - d.x, 10 - d.y)]
	check(sym, "open-room FOV symmetric")
	# A wall column blocks what is behind it.
	for y in range(5, 16):
		lv.tiles[Level.idx(12, y)] = Level.WALL
	vis = Fov.compute(lv, 10, 10, 6)
	check(vis[Level.idx(12, 10)] == 1, "blocking wall itself is visible")
	check(vis[Level.idx(14, 10)] == 0, "cell behind wall hidden")
	lv.tiles[Level.idx(12, 10)] = Level.DOOR
	vis = Fov.compute(lv, 10, 10, 6)
	check(vis[Level.idx(13, 10)] == 0, "closed door blocks sight")
	lv.tiles[Level.idx(12, 10)] = Level.OPEN_DOOR
	vis = Fov.compute(lv, 10, 10, 6)
	check(vis[Level.idx(13, 10)] == 1, "open door lets sight through")
	var line := Fov.line(Vector2i(0, 0), Vector2i(4, 2))
	check(line.size() == 4 and line[line.size() - 1] == Vector2i(4, 2), "bresenham line ends at target")


func _pathing() -> void:
	var lv := _open_level()
	for y in range(1, Level.H - 2):
		lv.tiles[Level.idx(8, y)] = Level.WALL
	var p := Pathing.find_path(lv, Vector2i(4, 4), Vector2i(12, 4))
	check(not p.is_empty() and p[p.size() - 1] == Vector2i(12, 4), "path found around wall")
	var ok := true
	for c in p:
		ok = ok and lv.passable(c.x, c.y)
	check(ok, "path only uses passable cells")
	lv.seen.fill(0)
	check(Pathing.find_path(lv, Vector2i(4, 4), Vector2i(12, 4), true).is_empty(), "known-only path refuses unexplored cells")
	var d := Pathing.distance_map(lv, 4, 4)
	check(d[Level.idx(5, 5)] == 1 and d[Level.idx(8, 4)] == -1, "distance map 8-way, walls -1")
