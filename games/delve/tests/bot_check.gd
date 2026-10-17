extends SceneTree
## Headless autoplay bot: plays whole runs through the public Run API only
## (explore -> loot -> fight -> descend). A god-mode run must walk all 12
## floors, kill the Ashen King and win; normal runs on many seeds must stay
## error-free and end in a recorded death or victory.
## godot --headless --path . --script tests/bot_check.gd

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
	var g := Bot.play(Run.create(Seeds.hash32(2026)), true, 9000)
	check(g.state == "won", "god-mode bot clears all 12 floors and wins (state %s, depth %d)" % [g.state, g.depth])
	check(g.deepest == 12 and g.kills > 0 and g.score() >= 5000, "god-mode run reached depth 12 with kills")
	var depths := []
	var causes := {}
	var finished := 0
	for s in 8:
		var r := Bot.play(Run.create(Seeds.hash32(s * 31 + 7)), false, 3000)
		depths.append(r.deepest)
		if r.state != "play":
			finished += 1
			causes[str(r.cause)] = int(causes.get(str(r.cause), 0)) + 1
		check(r.hp <= r.mhp and r.turns > 0, "seed %d run consistent" % s)
	depths.sort()
	check(finished >= 5, "most bot runs end in death or victory (%d/8)" % finished)
	check(depths[depths.size() / 2] >= 3, "median bot reaches depth 3+ (%s)" % str(depths))
	print("bot depths %s causes %s" % [str(depths), str(causes)])
	print("bot_check: %d passed, %d failed (%d ms)" % [_pass, _fail, Time.get_ticks_msec() - t0])
	quit(1 if _fail > 0 else 0)


class Bot:
	static func play(r: Run, god: bool, max_steps: int) -> Run:
		var floor_turns := 0
		var last_depth := r.depth
		for step in max_steps:
			if r.state != "play":
				break
			if god:
				r.mhp = maxi(r.mhp, 999)
				r.hp = r.mhp
				r.hunger = maxi(r.hunger, 500)
			if r.depth != last_depth:
				last_depth = r.depth
				floor_turns = 0
			floor_turns += 1
			if not act(r, floor_turns, god):
				r.act_search()
			if r.pending_descend:
				r.descend_sync()
		return r

	static func act(r: Run, floor_turns: int, god: bool) -> bool:
		var me := Vector2i(r.px, r.py)
		for m in r.lv.monsters:
			if Run.cheb(m.x - r.px, m.y - r.py) == 1:
				return r.act_move(Vector2i(m.x - r.px, m.y - r.py))
		if r.hp * 5 < r.mhp * 2:
			for i in r.inv.size():
				if Defs.cls(r.inv[i].id) == "potion" and (not r.kind_known(r.inv[i].id) or r.inv[i].id in ["p_heal", "p_vigor"]):
					return r.act_use(i)
		if r.hunger_state() >= 1:
			for i in r.inv.size():
				if Defs.cls(r.inv[i].id) == "food":
					return r.act_use(i)
		# Upgrade armour/weapons found on the way.
		for i in r.inv.size():
			var it: Dictionary = r.inv[i]
			if it.q:
				continue
			var c := Defs.cls(it.id)
			if c == "armour" and (r.armour().is_empty() or int(Defs.item(it.id).ac) > int(Defs.item(r.armour().id).ac)):
				if r.act_equip(i):
					return true
			if c == "weapon" and (r.weapon().is_empty() or int(Defs.item(it.id).dmg[1]) > int(Defs.item(r.weapon().id).dmg[1])):
				if r.act_equip(i):
					return true
		var here := r.lv.items_at(r.px, r.py)
		if not here.is_empty() and (r.inv.size() < Run.INV_MAX or here.any(func(e: Dictionary) -> bool: return e.it.id == "amulet")):
			if r.act_pickup():
				return true
		if r.on_stairs() and (floor_turns > 250 or god):
			return r.act_descend()
		var dist := Pathing.distance_map(r.lv, r.px, r.py, true)
		var target := Vector2i(-1, -1)
		var best := 1 << 30
		# Visible monsters (god mode hunts the king), items, then frontier.
		if god or r.depth == LevelGen.BOSS_DEPTH:
			for m in r.lv.monsters:
				if r.can_see(m) and dist[Level.idx(m.x, m.y)] > 0 and dist[Level.idx(m.x, m.y)] < best:
					best = dist[Level.idx(m.x, m.y)]
					target = Vector2i(m.x, m.y)
		if target.x < 0:
			for e in r.lv.items:
				var i := Level.idx(e.x, e.y)
				if e.s and dist[i] > 0 and dist[i] < best and (r.inv.size() < Run.INV_MAX or e.it.id == "amulet"):
					best = dist[i]
					target = Vector2i(e.x, e.y)
		if target.x < 0 and (not god or r.lv.stairs.x < 0 or r.lv.seen[Level.idx(r.lv.stairs.x, r.lv.stairs.y)] == 0):
			for i in dist.size():
				if dist[i] <= 0 or dist[i] >= best:
					continue
				var x := i % Level.W
				var y := i / Level.W
				for d: Vector2i in Pathing.DIRS:
					if Level.in_bounds(x + d.x, y + d.y) and r.lv.seen[Level.idx(x + d.x, y + d.y)] == 0:
						best = dist[i]
						target = Vector2i(x, y)
						break
		if target.x < 0 and r.lv.stairs.x >= 0 and dist[Level.idx(r.lv.stairs.x, r.lv.stairs.y)] > 0:
			target = r.lv.stairs
		if target.x < 0:
			return false
		var path := Pathing.find_path(r.lv, me, target, true)
		if path.is_empty():
			return false
		return r.act_move(path[0] - me)
