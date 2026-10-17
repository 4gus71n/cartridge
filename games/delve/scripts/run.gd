class_name Run
extends RefCounted
## One playthrough: player, pack, identification, current floor and the turn
## loop (player action -> statuses -> monster AI). No scene dependency, fully
## deterministic from the seed, serialises to a Dictionary for the autosave.

const FOV_RADIUS := 7
const INV_MAX := 18
const MAX_LOG := 80
const HEAR := 10 # awake monsters track the player within this walking distance

var run_seed := 0
var depth := 1
var deepest := 1
var turns := 0
var state := "play" # play | dead | won
var cause: Variant = ""
var kills := 0
var lv: Level
var rng := RandomNumberGenerator.new()

var px := 0
var py := 0
var hp := 20
var mhp := 20
var lvl := 1
var xp := 0
var might := 0
var hunger := Defs.HUNGER_START
var gold := 0
var haste := 0
var conf := 0
var pois := 0
var slept := 0
var regen := 0
var sight := false
var inv: Array = []
var known := {} # kind id -> true
var app := {} # kind id -> appearance ([key, hex] or scroll label)
var msgs: Array = [] # {m: text spec, k: kind, t: turn}

var fov := PackedByteArray()
var events: Array = [] # transient, for UI animation
var alerts := 0 # bumps when travel should stop
var pending_descend := false
var _vis_ids := {}
var _pdist := PackedInt32Array()


static func create(p_seed: int, first: Level = null) -> Run:
	var r := Run.new()
	r.run_seed = p_seed & Seeds.MASK
	r.rng = Seeds.make_rng(r.run_seed, 7)
	r._roll_appearances()
	var dagger := Spawn.item("short_sword")
	dagger.k = true
	dagger.q = true
	var armour := Spawn.item("leather")
	armour.k = true
	armour.q = true
	r.inv = [dagger, armour, Spawn.item("darts", 6), Spawn.item("ration")]
	r.msg("#MSG_WELCOME", 3)
	r.enter_level(first if first != null else LevelGen.generate(1, r.run_seed))
	return r


static func _shuffled(a: Array, r: RandomNumberGenerator) -> Array:
	for i in range(a.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t
	return a


func _roll_appearances() -> void:
	var a := Seeds.make_rng(run_seed, 3)
	var cols := _shuffled(Defs.POTION_COLORS.duplicate(), a)
	for i in Defs.POTION_KINDS.size():
		app[Defs.POTION_KINDS[i]] = cols[i]
	var woods := _shuffled(Defs.WAND_WOODS.duplicate(), a)
	for i in Defs.WAND_KINDS.size():
		app[Defs.WAND_KINDS[i]] = woods[i]
	var used := {}
	for k in Defs.SCROLL_KINDS:
		var label := ""
		while label == "" or used.has(label):
			label = ""
			for s in a.randi_range(2, 3):
				label += Defs.SYLLABLES[a.randi_range(0, Defs.SYLLABLES.size() - 1)]
			label = label.to_upper()
		used[label] = true
		app[k] = label


# --- floors ------------------------------------------------------------------

func enter_level(l: Level) -> void:
	lv = l
	depth = l.depth
	deepest = maxi(deepest, depth)
	px = l.start.x
	py = l.start.y
	sight = false
	pending_descend = false
	_vis_ids = {}
	update_fov()
	if depth == LevelGen.BOSS_DEPTH:
		msg("#MSG_BOSS_FLOOR", 3)
	else:
		msg({"f": "MSG_DEPTH", "a": [depth]}, 3)
	_check_visible()


func descend_sync() -> void:
	enter_level(LevelGen.generate(depth + 1, run_seed))


func update_fov() -> void:
	fov = Fov.compute(lv, px, py, FOV_RADIUS)
	for i in fov.size():
		if fov[i] == 1:
			lv.seen[i] = 1
	for e in lv.items:
		if fov[Level.idx(e.x, e.y)] == 1:
			e.s = true


func can_see_cell(x: int, y: int) -> bool:
	return Level.in_bounds(x, y) and fov[Level.idx(x, y)] == 1


func can_see(m: Dictionary) -> bool:
	return sight or can_see_cell(m.x, m.y)


func msg(spec: Variant, kind := 0) -> void:
	msgs.append({"m": spec, "k": kind, "t": turns})
	if msgs.size() > MAX_LOG:
		msgs = msgs.slice(msgs.size() - MAX_LOG)


# --- names -------------------------------------------------------------------

static func mname(m: Dictionary) -> String:
	return "#M_" + str(m.t).to_upper()


func kind_known(id: String) -> bool:
	return not (Defs.cls(id) in ["potion", "scroll", "wand"]) or known.has(id)


func item_name(it: Dictionary) -> Variant:
	var id: String = it.id
	var c := Defs.cls(id)
	var base: Variant = "#I_" + id.to_upper()
	match c:
		"gold":
			return {"f": "GOLD_N", "a": [it.n]}
		"weapon", "armour":
			if it.k:
				base = {"f": "ENCH", "a": [("+%d" % it.e) if it.e >= 0 else str(it.e), base]}
		"potion":
			if not known.has(id):
				base = {"f": "POTION_UNK", "a": ["#" + app[id][0]]}
		"scroll":
			if not known.has(id):
				base = {"f": "SCROLL_UNK", "a": [app[id]]}
		"wand":
			if not known.has(id):
				base = {"f": "WAND_UNK", "a": ["#" + app[id][0]]}
			elif it.k:
				base = {"f": "CHARGES", "a": [base, it.c]}
	if int(it.n) > 1:
		return {"f": "COUNT", "a": [base, it.n]}
	return base


func item_color(it: Dictionary) -> Color:
	var id: String = it.id
	match Defs.cls(id):
		"potion", "wand":
			return Color(app[id][1])
		"scroll":
			return Color(Defs.SCROLL_COLOR)
	return Color(Defs.item(id).get("c", "#ffffff"))


static func item_glyph(it: Dictionary) -> String:
	return Defs.item(it.id).g


## Description lines (text specs) for the inventory detail view.
func item_info(it: Dictionary) -> Array:
	var id: String = it.id
	var d: Dictionary = Defs.item(id)
	match Defs.cls(id):
		"weapon":
			var r := _weapon_dice(it)
			var out: Array = [{"f": "INFO_DMG", "a": ["%d-%d" % [r[0], r[1]]]}]
			if d.has("throw"):
				out.append("#INFO_THROWABLE")
			if not it.k:
				out.append("#INFO_UNK_ENCH")
			elif it.e < 0:
				out.append("#INFO_CURSED")
			return out
		"missile":
			return [{"f": "INFO_THROW", "a": ["%d-%d" % [d.throw[0], d.throw[1]]]}]
		"armour":
			var out: Array = [{"f": "INFO_AC", "a": [int(d.ac) + (int(it.e) if it.k else 0)]}]
			if not it.k:
				out.append("#INFO_UNK_ENCH")
			elif it.e < 0:
				out.append("#INFO_CURSED")
			return out
		"food":
			return ["#D_" + id.to_upper()]
		"potion", "scroll", "wand":
			if known.has(id):
				return ["#D_" + id.to_upper()]
			return ["#D_UNK_" + Defs.cls(id).to_upper()]
	return ["#D_" + id.to_upper()]


# --- player stats ------------------------------------------------------------

func _equipped(c: String) -> Dictionary:
	for it in inv:
		if it.q and Defs.cls(it.id) == c:
			return it
	return {}


func weapon() -> Dictionary:
	return _equipped("weapon")


func armour() -> Dictionary:
	return _equipped("armour")


func ac() -> int:
	var a := armour()
	if a.is_empty():
		return 1
	return 1 + int(Defs.item(a.id).ac) + int(a.e)


func to_hit() -> int:
	var w := weapon()
	var b := 3 + lvl + might / 2 + (int(w.e) if not w.is_empty() else 0)
	if hunger < Defs.WEAK:
		b -= 3
	return b


func _weapon_dice(w: Dictionary) -> Array:
	var d: Array = Defs.item(w.id).dmg
	return [int(d[0]) + int(w.e), int(d[1]) + int(w.e)]


func dmg_range() -> Array:
	var w := weapon()
	var r := [1, 3] if w.is_empty() else _weapon_dice(w)
	return [maxi(1, int(r[0]) + might), maxi(1, int(r[1]) + might)]


func hunger_state() -> int: # 0 ok, 1 hungry, 2 weak, 3 starving
	if hunger <= 0:
		return 3
	if hunger < Defs.WEAK:
		return 2
	if hunger < Defs.HUNGRY:
		return 1
	return 0


func xp_next() -> int:
	return Defs.XP_LEVELS[lvl] if lvl < Defs.XP_LEVELS.size() else xp


func score() -> int:
	return gold + xp + 200 * (deepest - 1) + kills * 5 + (5000 if state == "won" else 0)


func roll(r: Array) -> int:
	return rng.randi_range(int(r[0]), int(r[1]))


static func cheb(dx: int, dy: int) -> int:
	return maxi(absi(dx), absi(dy))


# --- player actions (return true when a turn passed) -------------------------

func act_move(dir: Vector2i) -> bool:
	if state != "play" or dir == Vector2i.ZERO:
		return false
	if conf > 0 and rng.randf() < 0.5:
		dir = Pathing.DIRS[rng.randi_range(0, 7)]
	var nx := px + dir.x
	var ny := py + dir.y
	var m := lv.monster_at(nx, ny)
	if not m.is_empty():
		_player_attack(m)
		return _end_turn()
	var t := lv.tile(nx, ny)
	if t == Level.WALL:
		if conf > 0:
			msg("#MSG_BUMP")
			return _end_turn()
		return false
	if t == Level.DOOR:
		lv.tiles[Level.idx(nx, ny)] = Level.OPEN_DOOR
		msg("#MSG_OPEN_DOOR")
		return _end_turn()
	px = nx
	py = ny
	_on_enter()
	return _end_turn()


func _on_enter() -> void:
	for e in lv.items_at(px, py):
		if e.it.id == "gold":
			gold += int(e.it.n)
			lv.items.erase(e)
			msg({"f": "MSG_GOLD", "a": [e.it.n]}, 1)
	var i := Level.idx(px, py)
	if lv.traps.has(i):
		_trigger_trap(lv.traps[i])
		if state != "play":
			return
	var here := lv.items_at(px, py)
	if here.size() == 1:
		msg({"f": "MSG_SEE_HERE", "a": [item_name(here[0].it)]})
	elif here.size() > 1:
		msg({"f": "MSG_SEE_SEVERAL", "a": [here.size()]})
	if lv.tile(px, py) == Level.STAIRS:
		msg("#MSG_ON_STAIRS", 3)


func _trigger_trap(tr: Dictionary) -> void:
	tr.f = true
	alerts += 1
	match tr.t:
		"dart":
			msg("#MSG_TRAP_DART", 2)
			if rng.randf() < 0.3:
				pois += rng.randi_range(3, 6)
				msg("#MSG_POISONED", 2)
			_hurt(rng.randi_range(1, 4) + depth / 3, "#CAUSE_TRAP")
		"teleport":
			msg("#MSG_TRAP_TELE", 2)
			_teleport_player()
		"alarm":
			msg("#MSG_TRAP_ALARM", 2)
			for m in lv.monsters:
				m.aw = true
				m.sl = 0


func act_wait() -> bool:
	if state != "play":
		return false
	return _end_turn()


func act_search() -> bool:
	if state != "play":
		return false
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var x := px + dx
			var y := py + dy
			if not Level.in_bounds(x, y):
				continue
			var i := Level.idx(x, y)
			if lv.traps.has(i) and not lv.traps[i].f and rng.randf() < 0.5:
				lv.traps[i].f = true
				msg("#MSG_FOUND_TRAP", 3)
	return _end_turn()


func act_pickup() -> bool:
	if state != "play":
		return false
	var here := lv.items_at(px, py)
	if here.is_empty():
		msg("#MSG_NOTHING_HERE")
		return false
	var took := false
	here.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.it.id == "amulet" and b.it.id != "amulet")
	for e in here:
		var it: Dictionary = e.it
		if it.id == "amulet":
			lv.items.erase(e)
			msg("#MSG_AMULET", 3)
			state = "won"
			cause = "#CAUSE_WON"
			return true
		if not _add_to_inv(it):
			msg("#MSG_PACK_FULL", 2)
			break
		lv.items.erase(e)
		took = true
		msg({"f": "MSG_PICKUP", "a": [item_name(it)]})
	return _end_turn() if took else false


func _add_to_inv(it: Dictionary) -> bool:
	if Defs.stackable(it.id):
		for o in inv:
			if o.id == it.id and o.e == it.e and not o.q:
				o.n = int(o.n) + int(it.n)
				return true
	if inv.size() >= INV_MAX:
		return false
	inv.append(it)
	return true


func act_descend() -> bool:
	if state != "play":
		return false
	if lv.tile(px, py) != Level.STAIRS:
		msg("#MSG_NO_STAIRS")
		return false
	pending_descend = true
	return true


func on_stairs() -> bool:
	return lv.tile(px, py) == Level.STAIRS


func _consume(i: int) -> void:
	inv[i].n = int(inv[i].n) - 1
	if int(inv[i].n) <= 0:
		inv.remove_at(i)


func _one(it: Dictionary) -> Dictionary:
	var c: Dictionary = it.duplicate()
	c.n = 1
	return c


func identify(id: String) -> void:
	known[id] = true


## Primary use of an item: quaff / read / eat / equip-toggle. Wands need a
## target (act_zap) and return false here.
func act_use(i: int) -> bool:
	if state != "play" or i < 0 or i >= inv.size():
		return false
	var it: Dictionary = inv[i]
	var id: String = it.id
	match Defs.cls(id):
		"potion":
			var spec: Variant = item_name(_one(it))
			_consume(i)
			identify(id)
			msg({"f": "MSG_QUAFF", "a": [spec]})
			_quaff(id)
			return _end_turn()
		"scroll":
			var spec2: Variant = item_name(_one(it))
			_consume(i)
			msg({"f": "MSG_READ", "a": [spec2]})
			identify(id)
			_read(id)
			return _end_turn()
		"food":
			_consume(i)
			hunger = mini(Defs.HUNGER_MAX, hunger + int(Defs.item(id).food))
			msg("#MSG_EAT_" + id.to_upper(), 1)
			return _end_turn()
		"weapon", "armour":
			return act_equip(i)
	return false


func act_equip(i: int) -> bool:
	if state != "play" or i < 0 or i >= inv.size():
		return false
	var it: Dictionary = inv[i]
	var c := Defs.cls(it.id)
	if not (c in ["weapon", "armour"]):
		return false
	if it.q:
		if int(it.e) < 0:
			msg("#MSG_CURSED_STUCK", 2)
			return false
		it.q = false
		msg({"f": "MSG_REMOVE", "a": [item_name(it)]})
		return _end_turn()
	var cur := _equipped(c)
	if not cur.is_empty():
		if int(cur.e) < 0:
			msg("#MSG_CURSED_STUCK", 2)
			return false
		cur.q = false
	it.q = true
	it.k = true
	msg({"f": "MSG_WIELD" if c == "weapon" else "MSG_WEAR", "a": [item_name(it)]})
	if int(it.e) < 0:
		msg("#MSG_CURSED", 2)
	return _end_turn()


func act_drop(i: int) -> bool:
	if state != "play" or i < 0 or i >= inv.size():
		return false
	var it: Dictionary = inv[i]
	if it.q and int(it.e) < 0:
		msg("#MSG_CURSED_STUCK", 2)
		return false
	it.q = false
	inv.remove_at(i)
	lv.items.append({"x": px, "y": py, "it": it, "s": true})
	msg({"f": "MSG_DROP", "a": [item_name(it)]})
	return _end_turn()


func act_throw(i: int, target: Vector2i) -> bool:
	if state != "play" or i < 0 or i >= inv.size() or target == Vector2i(px, py):
		return false
	var it: Dictionary = inv[i]
	if it.q and int(it.e) < 0:
		msg("#MSG_CURSED_STUCK", 2)
		return false
	var thrown: Dictionary = it.duplicate()
	thrown.n = 1
	thrown.q = false
	_consume(i)
	var me := Vector2i(px, py)
	var landing := me
	var hit_mon := {}
	for c in Fov.line(me, target, 8):
		if lv.solid(c.x, c.y):
			break
		landing = c
		var m := lv.monster_at(c.x, c.y)
		if not m.is_empty():
			hit_mon = m
			break
		if c == target:
			break
	events.append({"e": "bolt", "a": me, "b": landing, "c": item_color(thrown)})
	var id: String = thrown.id
	if not hit_mon.is_empty():
		var bonus := 2 if Defs.cls(id) == "missile" else 0
		if rng.randi_range(1, 20) + to_hit() + bonus >= 10 + int(Defs.mon(hit_mon.t).ac):
			var r: Array = Defs.item(id).get("throw", [1, 2])
			var dmg := roll(r) + (int(thrown.e) if Defs.cls(id) == "weapon" else 0) + might / 2
			msg({"f": "MSG_THROW_HIT", "a": [item_name(thrown), mname(hit_mon)]})
			_damage_mon(hit_mon, maxi(1, dmg))
		else:
			msg({"f": "MSG_THROW_MISS", "a": [item_name(thrown), mname(hit_mon)]})
			_wake(hit_mon)
	if Defs.cls(id) == "potion":
		msg("#MSG_SHATTER")
	else:
		lv.items.append({"x": landing.x, "y": landing.y, "it": thrown, "s": true})
	return _end_turn()


func act_zap(i: int, target: Vector2i) -> bool:
	if state != "play" or i < 0 or i >= inv.size() or target == Vector2i(px, py):
		return false
	var it: Dictionary = inv[i]
	var id: String = it.id
	if Defs.cls(id) != "wand":
		return false
	if int(it.c) <= 0:
		msg("#MSG_WAND_EMPTY")
		it.k = true
		return _end_turn()
	it.c = int(it.c) - 1
	identify(id)
	var me := Vector2i(px, py)
	var far := me + (target - me) * 12
	var cells := []
	for c in Fov.line(me, far, 9):
		if lv.solid(c.x, c.y):
			break
		cells.append(c)
	var hits := []
	for c in cells:
		var m := lv.monster_at(c.x, c.y)
		if not m.is_empty():
			hits.append(m)
	var end_cell: Vector2i = cells[cells.size() - 1] if not cells.is_empty() else me
	if id != "w_lightning" and not hits.is_empty():
		end_cell = Vector2i(hits[0].x, hits[0].y)
	events.append({"e": "bolt", "a": me, "b": end_cell, "c": app[id][1], "z": true})
	if hits.is_empty():
		msg({"f": "MSG_ZAP_NOTHING", "a": ["#I_" + id.to_upper()]})
		return _end_turn()
	match id:
		"w_lightning":
			for m in hits:
				msg({"f": "MSG_BOLT_HITS", "a": [mname(m)]})
				_damage_mon(m, roll([3, 18]) + depth / 2)
		"w_sleep":
			var m: Dictionary = hits[0]
			m.sl = 4 if Defs.mon(m.t).ai == "boss" else 14
			msg({"f": "MSG_SLEEPS", "a": [mname(m)]}, 1)
		"w_force":
			var m: Dictionary = hits[0]
			msg({"f": "MSG_FORCE", "a": [mname(m)]})
			var dir := Vector2i(signi(m.x - px), signi(m.y - py))
			for k in 2:
				var nx: int = m.x + dir.x
				var ny: int = m.y + dir.y
				if lv.solid(nx, ny) or not lv.passable(nx, ny) or not lv.monster_at(nx, ny).is_empty():
					break
				m.x = nx
				m.y = ny
			_damage_mon(m, roll([2, 10]))
	return _end_turn()


# --- potion / scroll effects ---------------------------------------------------

func _heal(n: int) -> void:
	hp = mini(mhp, hp + n)
	events.append({"e": "heal", "x": px, "y": py, "n": n})


func _quaff(id: String) -> void:
	match id:
		"p_heal":
			if hp >= mhp:
				mhp += 1
			_heal(8 + lvl * 2 + rng.randi_range(0, 6))
			pois = 0
			conf = 0
			msg("#MSG_P_HEAL", 1)
		"p_vigor":
			mhp += 3
			_heal(mhp)
			pois = 0
			msg("#MSG_P_VIGOR", 1)
		"p_might":
			might += 1
			msg("#MSG_P_MIGHT", 1)
		"p_haste":
			haste += 20
			msg("#MSG_P_HASTE", 1)
		"p_sight":
			sight = true
			_reveal_map()
			for e in lv.items:
				e.s = true
			msg("#MSG_P_SIGHT", 1)
		"p_confuse":
			conf += 8
			msg("#MSG_P_CONFUSE", 2)
		"p_poison":
			pois += 8
			msg("#MSG_P_POISON", 2)
		"p_sleep":
			slept += 5
			msg("#MSG_P_SLEEP", 2)
		"p_xp":
			if lvl < Defs.XP_LEVELS.size():
				gain_xp(xp_next() - xp)
			else:
				_heal(mhp)
			msg("#MSG_P_XP", 1)


func _read(id: String) -> void:
	match id:
		"s_identify":
			_identify_one()
		"s_teleport":
			_teleport_player()
			msg("#MSG_S_TELEPORT", 1)
		"s_enchant_w", "s_enchant_a":
			var it := weapon() if id == "s_enchant_w" else armour()
			if it.is_empty():
				msg("#MSG_S_ENCHANT_NONE")
			else:
				it.e = int(it.e) + 1
				it.k = true
				msg({"f": "MSG_S_ENCHANT", "a": [item_name(it)]}, 1)
		"s_map":
			_reveal_map()
			msg("#MSG_S_MAP", 1)
		"s_fear":
			for m in lv.monsters:
				if can_see_cell(m.x, m.y) and Defs.mon(m.t).ai != "boss":
					m.fl = 15
					m.aw = true
			msg("#MSG_S_FEAR", 1)
		"s_fire":
			msg("#MSG_S_FIRE", 2)
			events.append({"e": "burst", "x": px, "y": py})
			for m in lv.monsters.duplicate():
				if cheb(m.x - px, m.y - py) <= 2:
					_damage_mon(m, rng.randi_range(4, 10) + depth)
			_hurt(rng.randi_range(1, 4), "#CAUSE_FIRE")
		"s_summon":
			var n := rng.randi_range(2, 3)
			for k in n:
				var p := _free_near(Vector2i(px, py), 2)
				if p.x >= 0:
					var ids := Defs.monsters_for(depth)
					var m := Spawn.monster(ids[rng.randi_range(0, ids.size() - 1)], p.x, p.y, rng)
					m.aw = true
					lv.monsters.append(m)
			msg("#MSG_S_SUMMON", 2)


func _identify_one() -> void:
	var cand := []
	for it in inv:
		if not kind_known(it.id) or (Defs.cls(it.id) in ["weapon", "armour", "wand"] and not it.k):
			cand.append(it)
	if cand.is_empty():
		msg("#MSG_S_IDENTIFY_NONE")
		return
	var it: Dictionary = cand[rng.randi_range(0, cand.size() - 1)]
	identify(it.id)
	it.k = true
	msg({"f": "MSG_S_IDENTIFY", "a": [item_name(it)]}, 1)


func _reveal_map() -> void:
	for y in Level.H:
		for x in Level.W:
			if lv.tile(x, y) != Level.WALL:
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if Level.in_bounds(x + dx, y + dy):
							lv.seen[Level.idx(x + dx, y + dy)] = 1


func _teleport_player() -> void:
	var cells := lv.floor_cells()
	for attempt in 50:
		var c: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
		if lv.monster_at(c.x, c.y).is_empty() and cheb(c.x - px, c.y - py) > 4:
			px = c.x
			py = c.y
			break
	update_fov()


func _free_near(c: Vector2i, radius: int) -> Vector2i:
	for attempt in 40:
		var p := c + Vector2i(rng.randi_range(-radius, radius), rng.randi_range(-radius, radius))
		if lv.passable(p.x, p.y) and not lv.solid(p.x, p.y) and lv.monster_at(p.x, p.y).is_empty() and p != Vector2i(px, py):
			return p
	return Vector2i(-1, -1)


# --- combat -------------------------------------------------------------------

func gain_xp(n: int) -> void:
	xp += n
	while lvl < Defs.XP_LEVELS.size() and xp >= Defs.XP_LEVELS[lvl]:
		lvl += 1
		var g := rng.randi_range(3, 7)
		mhp += g
		hp += g
		msg({"f": "MSG_LEVEL_UP", "a": [lvl]}, 3)
		events.append({"e": "level"})


func _player_attack(m: Dictionary) -> void:
	_wake(m)
	if rng.randi_range(1, 20) + to_hit() >= 10 + int(Defs.mon(m.t).ac):
		msg({"f": "MSG_YOU_HIT", "a": [mname(m)]})
		_damage_mon(m, roll(dmg_range()))
	else:
		msg({"f": "MSG_YOU_MISS", "a": [mname(m)]})
		events.append({"e": "miss", "x": m.x, "y": m.y})


func _damage_mon(m: Dictionary, n: int) -> void:
	if int(m.hp) <= 0:
		return
	m.hp = int(m.hp) - n
	events.append({"e": "dmg", "x": m.x, "y": m.y, "n": n, "id": m.id})
	if int(m.hp) <= 0:
		_kill(m)
	else:
		_wake(m)
		m.sl = 0


func _kill(m: Dictionary) -> void:
	for i in lv.monsters.size():
		if is_same(lv.monsters[i], m):
			lv.monsters.remove_at(i)
			break
	kills += 1
	var d: Dictionary = Defs.mon(m.t)
	msg({"f": "MSG_KILL", "a": [mname(m)]}, 1)
	events.append({"e": "kill", "x": m.x, "y": m.y, "c": d.c})
	gain_xp(int(d.xp))
	if int(m.st) > 0:
		lv.items.append({"x": m.x, "y": m.y, "it": Spawn.item("gold", int(m.st)), "s": true})
	if d.ai == "boss":
		lv.items.append({"x": m.x, "y": m.y, "it": Spawn.item("amulet"), "s": true})
		msg("#MSG_KING_DIES", 3)
	elif rng.randf() < 0.12:
		lv.items.append({"x": m.x, "y": m.y, "it": Spawn.random_item(depth, rng), "s": true})


func _hurt(n: int, c: Variant) -> void:
	if state != "play":
		return
	hp -= n
	alerts += 1
	events.append({"e": "dmg", "x": px, "y": py, "n": n, "id": -1})
	if hp <= 0:
		hp = 0
		state = "dead"
		cause = c
		msg("#MSG_YOU_DIE", 2)


# --- turn loop ------------------------------------------------------------------

func _end_turn() -> bool:
	_tick()
	while slept > 0 and state == "play":
		slept -= 1
		if slept == 0:
			msg("#MSG_WAKE_UP")
		_tick()
	_check_visible()
	return true


func _tick() -> void:
	turns += 1
	var dur := 50 if haste > 0 else 100
	if haste > 0:
		haste -= 1
		if haste == 0:
			msg("#MSG_HASTE_END")
	if conf > 0:
		conf -= 1
		if conf == 0:
			msg("#MSG_CONF_END")
	var before := hunger_state()
	hunger -= 1
	if hunger_state() > before:
		msg(["", "#MSG_HUNGRY", "#MSG_WEAK", "#MSG_STARVING"][hunger_state()], 2)
		alerts += 1
	if pois > 0:
		pois -= 1
		_hurt(1, "#CAUSE_POISON")
	if hunger <= 0 and turns % 3 == 0:
		_hurt(1, "#CAUSE_STARVE")
	if hunger > 0 and pois == 0:
		regen += 1
		if regen >= maxi(3, 16 - lvl):
			regen = 0
			hp = mini(mhp, hp + 1)
	if state != "play":
		return
	update_fov()
	_monsters_act(dur)


func _check_visible() -> void:
	var ids := {}
	var fresh: Dictionary = {}
	for m in lv.monsters:
		if can_see_cell(m.x, m.y):
			ids[m.id] = true
			if not _vis_ids.has(m.id) and fresh.is_empty():
				fresh = m
	if not fresh.is_empty():
		alerts += 1
		msg({"f": "MSG_SPOT", "a": [mname(fresh)]})
	_vis_ids = ids


func _monsters_act(dur: int) -> void:
	_pdist = Pathing.distance_map(lv, px, py)
	for m in lv.monsters.duplicate():
		if state != "play":
			return
		if int(m.hp) <= 0:
			continue
		m.en = int(m.en) + int(Defs.mon(m.t).spd) * dur / 100
		while int(m.en) >= 100 and int(m.hp) > 0 and state == "play":
			m.en = int(m.en) - 100
			mon_act(m)


func _wake(m: Dictionary) -> void:
	if m.aw:
		return
	m.aw = true
	if "pack" in Defs.mon(m.t).flags:
		for o in lv.monsters:
			if o.t == m.t and cheb(o.x - m.x, o.y - m.y) <= 6:
				o.aw = true


func mon_act(m: Dictionary) -> void:
	var d: Dictionary = Defs.mon(m.t)
	var flags: Array = d.flags
	if "regen" in flags and int(m.hp) < int(m.mhp):
		m.hp = int(m.hp) + 1
	if int(m.cd) > 0:
		m.cd = int(m.cd) - 1
	if int(m.sl) > 0:
		m.sl = int(m.sl) - 1
		return
	var dist := cheb(m.x - px, m.y - py)
	var sees := can_see_cell(m.x, m.y)
	if not m.aw:
		if not sees:
			return
		var chance := 0.1 if "sleeps" in flags else 0.3
		if dist <= 2:
			chance *= 2.5
		if rng.randf() < chance:
			_wake(m)
		return
	if sees:
		m.lx = px
		m.ly = py
	if int(m.fl) > 0:
		m.fl = int(m.fl) - 1
	var ai: String = d.ai
	var afraid: bool = int(m.fl) > 0 or ("coward" in flags and int(m.hp) * 4 < int(m.mhp)) or (ai == "thief" and int(m.st) > 0)
	if afraid:
		if not _flee(m) and dist == 1:
			_mon_attack(m)
		return
	match ai:
		"erratic":
			if rng.randf() < 0.5:
				_random_step(m)
				return
		"ranged", "skittish", "boss":
			if ai == "boss" and _boss_special(m):
				return
			if ai == "skittish" and dist <= 1 and rng.randf() < 0.7 and _flee(m):
				return
			if sees and dist >= 2 and dist <= int(d.range) and int(m.cd) <= 0 and _clear_shot(m):
				_mon_shoot(m)
				return
			if ai == "ranged" and sees and dist == 2 and rng.randf() < 0.5 and _flee(m):
				return
	if dist == 1:
		_mon_attack(m)
		return
	_approach(m, sees)


func _boss_special(m: Dictionary) -> bool:
	if turns % 9 != 0:
		return false
	var near := 0
	for o in lv.monsters:
		if cheb(o.x - m.x, o.y - m.y) <= 6:
			near += 1
	if near > 4:
		return false
	for k in 2:
		var p := _free_near(Vector2i(m.x, m.y), 2)
		if p.x >= 0:
			var s := Spawn.monster("skeleton" if rng.randf() < 0.6 else "wraith", p.x, p.y, rng)
			s.aw = true
			lv.monsters.append(s)
	msg({"f": "MSG_BOSS_SUMMON", "a": [mname(m)]}, 2)
	alerts += 1
	return true


func _clear_shot(m: Dictionary) -> bool:
	var me := Vector2i(px, py)
	for c in Fov.line(Vector2i(m.x, m.y), me):
		if c == me:
			return true
		if lv.solid(c.x, c.y) or not lv.monster_at(c.x, c.y).is_empty():
			return false
	return true


func _mon_shoot(m: Dictionary) -> void:
	var d: Dictionary = Defs.mon(m.t)
	m.cd = 1 if d.ai != "ranged" else 2
	events.append({"e": "bolt", "a": Vector2i(m.x, m.y), "b": Vector2i(px, py), "c": d.c})
	msg({"f": "SHOOT_" + str(m.t).to_upper(), "a": [mname(m)]})
	if rng.randi_range(1, 20) + int(d.hit) >= 10 + ac():
		_hurt(roll(d.rdmg), mname(m))
	else:
		msg("#MSG_SHOT_MISS")


func _mon_attack(m: Dictionary) -> void:
	var d: Dictionary = Defs.mon(m.t)
	if rng.randi_range(1, 20) + int(d.hit) < 10 + ac():
		msg({"f": "MSG_MON_MISS", "a": [mname(m)]})
		return
	if d.ai == "thief" and gold > 0 and int(m.st) == 0:
		var amt := mini(gold, rng.randi_range(10, 25) + depth * 4)
		gold -= amt
		m.st = amt
		msg({"f": "MSG_STEAL", "a": [mname(m)]}, 2)
		alerts += 1
		var p := _free_near(Vector2i(m.x, m.y), 8)
		if p.x >= 0:
			m.x = p.x
			m.y = p.y
		return
	msg({"f": "MSG_MON_HIT", "a": [mname(m)]}, 2)
	_hurt(roll(d.dmg), mname(m))
	var flags: Array = d.flags
	if state != "play":
		return
	if "poison" in flags and rng.randf() < 0.4:
		pois += rng.randi_range(3, 6)
		msg("#MSG_POISONED", 2)
	if "drain" in flags and rng.randf() < 0.35:
		mhp = maxi(10, mhp - 1)
		hp = mini(hp, mhp)
		xp = maxi(0, xp - xp / 10)
		msg("#MSG_DRAINED", 2)


func _free_for_mon(x: int, y: int) -> bool:
	return lv.passable(x, y) and not (x == px and y == py) and lv.monster_at(x, y).is_empty()


func _step(m: Dictionary, to: Vector2i) -> void:
	var i := Level.idx(to.x, to.y)
	if lv.tiles[i] == Level.DOOR:
		lv.tiles[i] = Level.OPEN_DOOR
		return
	m.x = to.x
	m.y = to.y


func _approach(m: Dictionary, sees: bool) -> void:
	var here := _pdist[Level.idx(m.x, m.y)]
	if here < 0 or (not sees and here > HEAR):
		if rng.randf() < 0.5:
			_random_step(m)
		return
	var best := []
	var best_d := here
	for dir: Vector2i in Pathing.DIRS:
		var n := Vector2i(m.x, m.y) + dir
		if not Level.in_bounds(n.x, n.y) or not _free_for_mon(n.x, n.y):
			continue
		var nd := _pdist[Level.idx(n.x, n.y)]
		if nd < 0:
			continue
		if nd < best_d:
			best_d = nd
			best = [n]
		elif nd == best_d and nd < here:
			best.append(n)
	if not best.is_empty():
		_step(m, best[rng.randi_range(0, best.size() - 1)])


func _flee(m: Dictionary) -> bool:
	var here := _pdist[Level.idx(m.x, m.y)]
	var best := Vector2i(-1, -1)
	var best_d := here
	for dir: Vector2i in Pathing.DIRS:
		var n := Vector2i(m.x, m.y) + dir
		if not Level.in_bounds(n.x, n.y) or not _free_for_mon(n.x, n.y):
			continue
		var nd := _pdist[Level.idx(n.x, n.y)]
		if nd > best_d:
			best_d = nd
			best = n
	if best.x < 0:
		return false
	_step(m, best)
	return true


func _random_step(m: Dictionary) -> void:
	var dir: Vector2i = Pathing.DIRS[rng.randi_range(0, 7)]
	var n := Vector2i(m.x, m.y) + dir
	if Level.in_bounds(n.x, n.y) and _free_for_mon(n.x, n.y):
		_step(m, n)


# --- inspection -------------------------------------------------------------------

## Text specs describing a cell for the long-press inspector.
func describe(x: int, y: int) -> Array:
	if not Level.in_bounds(x, y) or lv.seen[Level.idx(x, y)] == 0:
		return ["#INS_UNKNOWN"]
	if x == px and y == py:
		return [{"f": "INS_YOU", "a": [hp, mhp, lvl]}]
	var out: Array = []
	var m := lv.monster_at(x, y)
	if not m.is_empty() and can_see(m):
		var d: Dictionary = Defs.mon(m.t)
		var st := "#INS_AWAKE"
		if int(m.sl) > 0 or not m.aw:
			st = "#INS_ASLEEP"
		elif int(m.fl) > 0:
			st = "#INS_AFRAID"
		out.append({"f": "INS_MON", "a": ["#MN_" + str(m.t).to_upper(), m.hp, m.mhp, st]})
		var traits: Array = []
		var tag := {"ranged": "TR_RANGED", "skittish": "TR_RANGED", "thief": "TR_THIEF", "erratic": "TR_ERRATIC", "boss": "TR_BOSS"}
		if tag.has(d.ai):
			traits.append("#" + tag[d.ai])
		if int(d.spd) > 100:
			traits.append("#TR_FAST")
		elif int(d.spd) < 100:
			traits.append("#TR_SLOW")
		for f in d.flags:
			if f in ["pack", "poison", "drain", "regen", "coward"]:
				traits.append("#TR_" + str(f).to_upper())
		if not traits.is_empty():
			var t: Variant = traits[0]
			for k in range(1, traits.size()):
				t = {"f": "LIST2", "a": [t, traits[k]]}
			out.append(t)
	for e in lv.items_at(x, y):
		if e.s:
			out.append(item_name(e.it))
	var i := Level.idx(x, y)
	if lv.traps.has(i) and lv.traps[i].f:
		out.append("#TRAP_" + str(lv.traps[i].t).to_upper())
	if out.is_empty():
		out.append(["#T_WALL", "#T_FLOOR", "#T_CORRIDOR", "#T_DOOR", "#T_OPEN_DOOR", "#T_STAIRS", "#T_UPSTAIRS"][lv.tile(x, y)])
	return out


# --- save / load --------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"v": 1, "seed": run_seed, "depth": depth, "deepest": deepest, "turns": turns, "state": state,
		"cause": cause, "kills": kills, "rng": rng.state,
		"p": [px, py, hp, mhp, lvl, xp, might, hunger, gold, haste, conf, pois, slept, regen, 1 if sight else 0],
		"inv": inv.duplicate(true), "known": known.duplicate(), "app": app.duplicate(true),
		"log": msgs.slice(maxi(0, msgs.size() - 30)), "lv": lv.to_dict(), "vis": _vis_ids.keys(),
	}


static func from_dict(d: Dictionary) -> Run:
	var r := Run.new()
	r.run_seed = int(d.seed)
	r.depth = int(d.depth)
	r.deepest = int(d.deepest)
	r.turns = int(d.turns)
	r.state = d.state
	r.cause = d.cause
	r.kills = int(d.kills)
	r.rng.state = int(d.rng)
	var p: Array = d.p
	r.px = p[0]
	r.py = p[1]
	r.hp = p[2]
	r.mhp = p[3]
	r.lvl = p[4]
	r.xp = p[5]
	r.might = p[6]
	r.hunger = p[7]
	r.gold = p[8]
	r.haste = p[9]
	r.conf = p[10]
	r.pois = p[11]
	r.slept = p[12]
	r.regen = p[13]
	r.sight = int(p[14]) == 1
	r.inv = d.inv.duplicate(true)
	r.known = d.known.duplicate()
	r.app = d.app.duplicate(true)
	r.msgs = d.log.duplicate(true)
	r.lv = Level.from_dict(d.lv)
	for id in d.vis:
		r._vis_ids[id] = true
	r.update_fov()
	return r
