extends SceneTree
## Game-rule checks on Run: combat, identification, inventory, hunger,
## save/load mid-run, monster AI steps, death, score and the win.
## godot --headless --path . --script tests/logic_check.gd

const TEST_PATH := "user://logic_check_test.cfg"

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	_combat()
	_identification()
	_inventory()
	_hunger()
	_save_load()
	_ai()
	_death_and_score()
	_win()
	_wands_scrolls()
	print("logic_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


## An empty walled arena with the player at (10, 10).
func arena(seed := 1) -> Run:
	var lv := Level.new()
	lv.depth = 3
	for y in range(1, 30):
		for x in range(1, 30):
			lv.tiles[Level.idx(x, y)] = Level.FLOOR
	lv.start = Vector2i(10, 10)
	lv.tiles[Level.idx(20, 20)] = Level.STAIRS
	lv.stairs = Vector2i(20, 20)
	return Run.create(seed, lv)


func put(r: Run, type: String, x: int, y: int, awake := true) -> Dictionary:
	var m := Spawn.monster(type, x, y, r.rng)
	m.aw = awake
	r.lv.monsters.append(m)
	return m


func _combat() -> void:
	var r := arena()
	check(r.hp == r.mhp and r.lvl == 1 and r.depth == 3, "fresh run state")
	check(not r.weapon().is_empty() and r.weapon().id == "short_sword", "starts wielding a short sword")
	check(r.ac() == 3, "leather armour gives AC 3 (%d)" % r.ac())
	var m := put(r, "rat", 11, 10)
	var hits := 0
	for i in 40:
		if r.lv.monsters.is_empty():
			break
		r.act_move(Vector2i(1, 0))
		hits += 1
	check(r.lv.monsters.is_empty(), "attacking an adjacent rat kills it (%d swings)" % hits)
	check(r.kills == 1 and r.xp >= int(Defs.mon("rat").xp), "kill counted and XP gained")
	check(r.px == 10, "attacking does not move the player")
	# Level up.
	r.gain_xp(Defs.XP_LEVELS[2] - r.xp)
	check(r.lvl == 3 and r.mhp > 20, "XP thresholds raise level and max HP")
	# Damage numbers are emitted for the UI.
	var kinds := {}
	for e in r.events:
		kinds[e.e] = true
	check(kinds.has("dmg") and kinds.has("kill"), "combat emits UI events")
	# Monsters hit back.
	var r2 := arena(5)
	put(r2, "orc", 11, 10)
	var hp0 := r2.hp
	for i in 12:
		r2.act_wait()
	check(r2.hp < hp0 or r2.state == "dead", "adjacent orc damages a waiting player")


func _identification() -> void:
	var a := arena(11)
	var b := arena(12)
	var cols := {}
	for k in Defs.POTION_KINDS:
		cols[a.app[k][0]] = true
	check(cols.size() == Defs.POTION_KINDS.size(), "potion colours distinct within a run")
	var labels := {}
	for k in Defs.SCROLL_KINDS:
		labels[a.app[k]] = true
	check(labels.size() == Defs.SCROLL_KINDS.size(), "scroll labels distinct within a run")
	var differs := false
	for k in Defs.POTION_KINDS:
		if a.app[k][0] != b.app[k][0]:
			differs = true
	check(differs, "appearances re-rolled per run seed")
	check(arena(11).app == a.app, "appearances deterministic per seed")
	check(not a.kind_known("p_heal") and a.kind_known("dagger"), "potions start unknown, weapons known")
	TranslationServer.set_locale("en")
	var it := Spawn.item("p_heal")
	var unk := Txt.render(a.item_name(it))
	check(unk.ends_with("potion") and not unk.contains("healing"), "unknown potion shows colour (%s)" % unk)
	a.inv.append(it)
	a.hp = 5
	a.act_use(a.inv.size() - 1)
	check(a.kind_known("p_heal") and a.hp > 5, "drinking identifies and heals")
	check(Txt.render(a.item_name(Spawn.item("p_heal"))) == "potion of healing", "identified name shown")
	var sc := Txt.render(a.item_name(Spawn.item("s_map")))
	check(sc.begins_with("scroll labelled "), "unknown scroll shows label (%s)" % sc)
	var w := Spawn.item("long_sword")
	w.e = 2
	check(Txt.render(a.item_name(w)) == "long sword", "enchant hidden until known")
	w.k = true
	check(Txt.render(a.item_name(w)) == "+2 long sword", "known enchant shown")
	TranslationServer.set_locale("es")
	check(Txt.render(a.item_name(w)) == "espada larga +2", "ES enchant order")
	check(Txt.sentence({"f": "MSG_YOU_HIT", "a": ["#M_ORC"]}) == "Golpeas al orco.", "ES contraction a+el")
	TranslationServer.set_locale("en")
	# Scroll of identify reveals one unknown item.
	var c := arena(13)
	c.inv.append(Spawn.item("w_sleep"))
	c.inv.append(Spawn.item("s_identify"))
	c.act_use(c.inv.size() - 1)
	check(c.kind_known("s_identify") and c.kind_known("w_sleep"), "scroll of identify identifies the unknown wand")


func _inventory() -> void:
	var r := arena(21)
	var n0 := r.inv.size()
	r.lv.items.append({"x": 10, "y": 10, "it": Spawn.item("darts", 3), "s": true})
	check(r.act_pickup(), "pick up takes a turn")
	check(r.inv.size() == n0 and r.inv[2].n == 9, "darts stack onto existing stack")
	# Drop & pick back up.
	var idx := r.inv.size() - 1
	var dropped: Dictionary = r.inv[idx]
	r.act_drop(idx)
	check(r.inv.size() == n0 - 1 and r.lv.items_at(10, 10).size() == 1, "drop puts item on floor")
	r.act_pickup()
	check(r.inv.size() == n0 and r.inv.back().id == dropped.id, "item picked back up")
	# Equip swap and curses.
	var sword := Spawn.item("short_sword")
	sword.e = -1
	r.inv.append(sword)
	r.act_equip(r.inv.size() - 1)
	check(r.weapon().id == "short_sword" and sword.k, "wielding swaps weapon and reveals enchant")
	check(not r.act_equip(r.inv.size() - 1), "cursed weapon can't be removed")
	check(not r.act_drop(r.inv.size() - 1), "cursed weapon can't be dropped")
	r.inv.append(Spawn.item("s_enchant_w"))
	r.known["s_enchant_w"] = true
	r.act_use(r.inv.size() - 1)
	check(int(sword.e) == 0, "enchant scroll lifts the curse")
	check(r.act_equip(r.inv.find(sword)), "uncursed weapon can be removed")
	check(r.weapon().is_empty() and r.dmg_range() == [1, 3], "bare hands do 1-3")
	# Pack limit.
	while r.inv.size() < Run.INV_MAX:
		r.inv.append(Spawn.item("mace"))
	r.lv.items.append({"x": 10, "y": 10, "it": Spawn.item("spear"), "s": true})
	check(not r.act_pickup() and r.inv.size() == Run.INV_MAX, "full pack refuses pickup")
	# Throwing.
	var t := arena(22)
	var m := put(t, "zombie", 14, 10, false)
	var darts := 2
	var before := int(t.inv[darts].n)
	t.act_throw(darts, Vector2i(14, 10))
	check(int(t.inv[darts].n) == before - 1, "throwing uses one dart")
	var landed := t.lv.items_at(14, 10).size() + t.lv.items_at(13, 10).size()
	check(landed == 1 or t.lv.items.size() > 0, "thrown dart lands on the floor")
	check(m.aw, "thrown missile wakes the target")
	# Gold auto-pickup.
	var g := arena(23)
	g.lv.items.append({"x": 11, "y": 10, "it": Spawn.item("gold", 17), "s": true})
	g.act_move(Vector2i(1, 0))
	check(g.gold == 17, "walking over gold picks it up")
	# Doors open on bump.
	g.lv.tiles[Level.idx(12, 10)] = Level.DOOR
	g.act_move(Vector2i(1, 0))
	check(g.lv.tile(12, 10) == Level.OPEN_DOOR and g.px == 11, "bumping a door opens it")


func _hunger() -> void:
	var r := arena(31)
	r.hunger = Defs.HUNGRY + 2
	for i in 4:
		r.act_wait()
	check(r.hunger_state() == 1, "becomes Hungry under threshold")
	var found := false
	for e in r.msgs:
		if str(e.m) == "#MSG_HUNGRY":
			found = true
	check(found, "hungry message logged")
	var ration := r.inv.size() - 1
	check(r.inv[ration].id == "ration", "starting ration in pack")
	r.act_use(ration)
	check(r.hunger > Defs.HUNGRY + 800 and r.hunger_state() == 0, "eating restores food")
	var s := arena(32)
	s.hunger = 1
	s.inv = s.inv.filter(func(it: Dictionary) -> bool: return Defs.cls(it.id) != "food")
	for i in 400:
		if s.state != "play":
			break
		s.act_wait()
	check(s.state == "dead" and str(s.cause) == "#CAUSE_STARVE", "starvation kills (cause %s)" % str(s.cause))
	var w := arena(33)
	var base := w.to_hit()
	w.hunger = Defs.WEAK - 1
	check(w.to_hit() == base - 3, "Weak lowers accuracy")


func _save_load() -> void:
	var r := Run.create(4242)
	for i in 30:
		r.act_move(Pathing.DIRS[i % 8])
	var d := r.to_dict()
	# Round-trip through a real ConfigFile like the autosave does.
	var cfg := ConfigFile.new()
	cfg.set_value("run", "state", d)
	cfg.save(TEST_PATH)
	var cfg2 := ConfigFile.new()
	cfg2.load(TEST_PATH)
	var r2 := Run.from_dict(cfg2.get_value("run", "state"))
	check(r2.px == r.px and r2.py == r.py and r2.hp == r.hp and r2.turns == r.turns, "player restored")
	check(r2.lv.tiles == r.lv.tiles and r2.lv.seen == r.lv.seen, "map + memory restored")
	check(r2.lv.monsters.size() == r.lv.monsters.size() and r2.inv.size() == r.inv.size(), "monsters + pack restored")
	check(r2.app == r.app, "appearances restored")
	# Determinism after load: both continue identically.
	for i in 40:
		var dir: Vector2i = Pathing.DIRS[(i * 3) % 8]
		r.act_move(dir)
		r2.act_move(dir)
	check(r.px == r2.px and r.py == r2.py and r.hp == r2.hp and r.rng.state == r2.rng.state, "loaded run continues identically")
	# Settings autosave.
	var settings: Node = root.get_node("Settings")
	settings.load_from(TEST_PATH)
	settings.store_run(r.to_dict())
	settings.load_from(TEST_PATH)
	check(settings.has_run() and int(settings.saved_run().turns) == r.turns, "Settings persists the run file")
	settings.clear_run()
	settings.load_from(TEST_PATH)
	check(not settings.has_run(), "clear_run removes the save")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func _ai() -> void:
	# Melee approaches.
	var r := arena(41)
	var m := put(r, "skeleton", 15, 10)
	r.act_wait()
	check(m.x < 15, "melee monster steps toward the player")
	# Sleeping monster out of view stays put.
	var r1 := arena(42)
	var s := put(r1, "zombie", 25, 25, false)
	r1.lv.tiles[Level.idx(24, 24)] = Level.WALL
	for i in 3:
		r1.act_wait()
	check(s.x == 25 and s.y == 25 and not s.aw, "sleeping monster out of sight doesn't move")
	# Ranged shoots from a distance.
	var r2 := arena(43)
	var a := put(r2, "archer", 14, 10)
	var shot := false
	for i in 6:
		r2.act_wait()
		for e in r2.events:
			if e.e == "bolt" and e.a != Vector2i(r2.px, r2.py):
				shot = true
	check(shot, "archer shoots from range")
	check(Run.cheb(a.x - r2.px, a.y - r2.py) >= 2, "archer keeps its distance")
	# Coward flees when hurt.
	var r3 := arena(44)
	var g := put(r3, "goblin", 12, 10)
	g.hp = 1
	g.mhp = 8
	r3.act_wait()
	check(g.x > 12, "wounded goblin flees")
	# Thief steals and runs.
	var r4 := arena(45)
	r4.gold = 100
	var imp := put(r4, "imp", 11, 10)
	for i in 30:
		if r4.gold < 100:
			break
		r4.act_wait()
	check(r4.gold < 100 and int(imp.st) > 0, "imp steals gold")
	r4.lv.monsters.erase(imp)
	# Pack wakes together.
	var r5 := arena(46)
	var o1 := put(r5, "orc", 18, 18, false)
	var o2 := put(r5, "orc", 19, 18, false)
	r5._wake(o1)
	check(o2.aw, "waking a pack member wakes the pack")
	# Fear scroll.
	var r6 := arena(47)
	var k := put(r6, "orc", 12, 10)
	r6.known["s_fear"] = true
	r6.inv.append(Spawn.item("s_fear"))
	r6.act_use(r6.inv.size() - 1)
	check(int(k.fl) > 0 and k.x >= 12, "dread scroll makes monsters flee")
	# Boss summons.
	var r7 := arena(48)
	var king := put(r7, "king", 16, 10)
	king.hp = 999
	var n0 := r7.lv.monsters.size()
	for i in 12:
		r7.hp = r7.mhp
		r7.act_wait()
	check(r7.lv.monsters.size() > n0, "the king summons minions")


func _death_and_score() -> void:
	var r := arena(51)
	put(r, "ogre", 11, 10)
	r.hp = 1
	for i in 40:
		if r.state != "play":
			break
		r.act_wait()
	check(r.state == "dead" and str(r.cause) == "#M_OGRE", "dying to a monster records its name")
	check(not r.act_wait() and not r.act_move(Vector2i(1, 0)), "no actions after death")
	r.gold = 50
	r.xp = 30
	check(r.score() == 50 + 30 + 200 * (r.deepest - 1) + r.kills * 5, "score formula")
	var settings: Node = root.get_node("Settings")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	settings.load_from(TEST_PATH)
	for sc in [300, 100, 500]:
		settings.add_score({"score": sc, "depth": 2, "turns": 10, "lvl": 1, "won": false, "cause": "#M_RAT", "code": "AAAAAA"})
	var rank: int = settings.add_score({"score": 400, "depth": 3, "turns": 10, "lvl": 1, "won": false, "cause": "#M_RAT", "code": "B"})
	check(rank == 1 and int(settings.scores[0].score) == 500, "high scores sorted, rank returned")
	for i in 12:
		settings.add_score({"score": 1, "depth": 1, "turns": 1, "lvl": 1, "won": false, "cause": "#M_RAT", "code": "C"})
	settings.load_from(TEST_PATH)
	check(settings.scores.size() == 10 and settings.runs == 16, "table capped at 10 and persisted")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func _win() -> void:
	var r := arena(61)
	r.lv.items.append({"x": 11, "y": 10, "it": Spawn.item("amulet"), "s": true})
	r.act_move(Vector2i(1, 0))
	r.act_pickup()
	check(r.state == "won", "taking the Heart of Embers wins")
	check(r.score() >= 5000, "victory bonus in score")
	# Killing the king drops it.
	var b := arena(62)
	var king := put(b, "king", 11, 10)
	king.hp = 1
	b.known.clear()
	for i in 30:
		if b.lv.monsters.is_empty():
			break
		b.hp = b.mhp
		b.act_move(Vector2i(1, 0))
	var dropped := false
	for e in b.lv.items:
		if e.it.id == "amulet":
			dropped = true
	check(dropped, "the Ashen King drops the amulet")


func _wands_scrolls() -> void:
	var r := arena(71)
	var m1 := put(r, "troll", 13, 10)
	var m2 := put(r, "troll", 15, 10)
	var wand := Spawn.item("w_lightning")
	wand.c = 3
	r.inv.append(wand)
	var h1 := int(m1.hp)
	var h2 := int(m2.hp)
	r.act_zap(r.inv.size() - 1, Vector2i(13, 10))
	check(int(m1.hp) < h1 and int(m2.hp) < h2, "lightning pierces a line of monsters")
	check(r.kind_known("w_lightning") and int(wand.c) == 2, "zapping identifies and uses a charge")
	var s := put(r, "orc", 10, 13)
	var sl := Spawn.item("w_sleep")
	r.inv.append(sl)
	r.act_zap(r.inv.size() - 1, Vector2i(10, 12))
	check(int(s.sl) > 0, "slumber wand puts a monster to sleep")
	var t := arena(72)
	t.known["s_teleport"] = true
	t.inv.append(Spawn.item("s_teleport"))
	t.act_use(t.inv.size() - 1)
	check(t.px != 10 or t.py != 10, "teleport scroll moves the player")
	var mp := arena(73)
	mp.inv.append(Spawn.item("s_map"))
	mp.act_use(mp.inv.size() - 1)
	check(mp.lv.seen[Level.idx(28, 28)] == 1, "mapping reveals the floor")
	var trap := arena(74)
	trap.lv.traps[Level.idx(11, 10)] = {"t": "dart", "f": false}
	var hp0 := trap.hp
	trap.act_move(Vector2i(1, 0))
	check(trap.hp < hp0 and trap.lv.traps[Level.idx(11, 10)].f, "dart trap hurts and becomes known")
	var srch := arena(75)
	srch.lv.traps[Level.idx(11, 11)] = {"t": "alarm", "f": false}
	for i in 10:
		srch.act_search()
	check(srch.lv.traps[Level.idx(11, 11)].f, "searching finds adjacent traps")
	var desc := Txt.render(srch.describe(11, 11)[0])
	check(desc == "Alarm trap", "inspect describes found trap (%s)" % desc)
