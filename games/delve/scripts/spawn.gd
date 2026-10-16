class_name Spawn
extends RefCounted
## Factories for monsters and items (shared by LevelGen and Run).


static func monster(type: String, x: int, y: int, rng: RandomNumberGenerator) -> Dictionary:
	var d: Dictionary = Defs.mon(type)
	var hp: int = d.hp + rng.randi_range(0, int(d.hp) / 4)
	return {
		"id": rng.randi() & 0x3FFFFFFF, "t": type, "x": x, "y": y, "hp": hp, "mhp": hp,
		"en": rng.randi_range(0, 99), "aw": false, "fl": 0, "sl": 0, "st": 0, "cd": 0,
		"lx": -1, "ly": -1,
	}


static func item(id: String, n := 1) -> Dictionary:
	var it := {"id": id, "n": n, "e": 0, "k": false, "c": 0}
	if Defs.cls(id) == "wand":
		it.c = 4
	if Defs.cls(id) in ["food", "gold", "amulet", "missile"]:
		it.k = true
	return it


static func _weighted(ids: Array, depth: int, rng: RandomNumberGenerator) -> String:
	var total := 0
	for id in ids:
		if Defs.item(id).d <= depth:
			total += int(Defs.item(id).w)
	var r := rng.randi_range(1, maxi(total, 1))
	for id in ids:
		if Defs.item(id).d <= depth:
			r -= int(Defs.item(id).w)
			if r <= 0:
				return id
	return ids[0]


static func random_item(depth: int, rng: RandomNumberGenerator) -> Dictionary:
	var roll := rng.randi_range(1, 100)
	var it: Dictionary
	if roll <= 26:
		it = item(_weighted(Defs.POTION_KINDS, depth, rng))
	elif roll <= 48:
		it = item(_weighted(Defs.SCROLL_KINDS, depth, rng))
	elif roll <= 60:
		it = item(_weighted(["ration", "apple"], depth, rng))
	elif roll <= 70:
		it = item(_weighted(["dagger", "short_sword", "spear", "mace", "long_sword", "battle_axe"], depth, rng))
		it.e = _enchant(depth, rng)
	elif roll <= 76:
		it = item("darts", rng.randi_range(4, 9))
	elif roll <= 86:
		it = item(_weighted(["leather", "ring_mail", "chain_mail", "scale_mail", "plate"], depth, rng))
		it.e = _enchant(depth, rng)
	elif roll <= 93:
		it = item(_weighted(Defs.WAND_KINDS, depth, rng))
		it.c = rng.randi_range(3, 6)
	else:
		it = item(_weighted(Defs.POTION_KINDS, depth, rng))
	return it


static func _enchant(depth: int, rng: RandomNumberGenerator) -> int:
	var r := rng.randf()
	if r < 0.12:
		return -1
	if r < 0.7:
		return 0
	if r < 0.92:
		return 1
	return 2 if depth < 7 else 3
