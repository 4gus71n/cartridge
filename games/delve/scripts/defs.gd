class_name Defs
extends RefCounted
## Static game content: monsters, items, appearances, traps. All original.
## Display names live in i18n/strings.csv under M_<ID> / I_<ID> keys.

const DEPTHS := 12

# ai: melee | erratic | ranged | thief | skittish | boss
# flags: pack, sleeps, coward, regen, poison, drain, summon
const MONSTERS := {
	"rat": {"g": "r", "c": "#c49a6c", "hp": 4, "ac": 1, "hit": 0, "dmg": [1, 3], "spd": 100, "xp": 2, "d": [1, 4], "ai": "melee", "flags": ["coward"]},
	"bat": {"g": "b", "c": "#b48ae6", "hp": 4, "ac": 3, "hit": 1, "dmg": [1, 3], "spd": 150, "xp": 3, "d": [1, 5], "ai": "erratic", "flags": []},
	"goblin": {"g": "g", "c": "#7fd36b", "hp": 5, "ac": 2, "hit": 1, "dmg": [1, 4], "spd": 100, "xp": 5, "d": [2, 6], "ai": "melee", "flags": ["pack", "coward"]},
	"dog": {"g": "d", "c": "#d9b072", "hp": 6, "ac": 2, "hit": 1, "dmg": [1, 4], "spd": 150, "xp": 5, "d": [2, 6], "ai": "melee", "flags": ["pack"]},
	"slime": {"g": "j", "c": "#5cf28f", "hp": 11, "ac": 0, "hit": 1, "dmg": [1, 5], "spd": 50, "xp": 6, "d": [1, 7], "ai": "melee", "flags": ["sleeps"]},
	"archer": {"g": "g", "c": "#f2d45c", "hp": 7, "ac": 2, "hit": 2, "dmg": [1, 3], "spd": 100, "xp": 8, "d": [3, 8], "ai": "ranged", "rdmg": [1, 6], "range": 6, "flags": ["coward"]},
	"imp": {"g": "i", "c": "#ff7fd1", "hp": 7, "ac": 4, "hit": 3, "dmg": [1, 2], "spd": 150, "xp": 9, "d": [3, 9], "ai": "thief", "flags": []},
	"zombie": {"g": "Z", "c": "#9cba84", "hp": 18, "ac": 1, "hit": 2, "dmg": [1, 7], "spd": 50, "xp": 11, "d": [3, 8], "ai": "melee", "flags": ["sleeps"]},
	"skeleton": {"g": "s", "c": "#ece6d2", "hp": 15, "ac": 4, "hit": 3, "dmg": [1, 8], "spd": 100, "xp": 13, "d": [5, 10], "ai": "melee", "flags": []},
	"orc": {"g": "o", "c": "#e4704f", "hp": 16, "ac": 4, "hit": 3, "dmg": [1, 8], "spd": 100, "xp": 15, "d": [5, 10], "ai": "melee", "flags": ["pack"]},
	"spider": {"g": "S", "c": "#c25cf0", "hp": 15, "ac": 5, "hit": 4, "dmg": [1, 6], "spd": 150, "xp": 19, "d": [6, 11], "ai": "melee", "flags": ["poison", "sleeps"]},
	"wisp": {"g": "w", "c": "#7fe9ff", "hp": 10, "ac": 7, "hit": 5, "dmg": [1, 3], "spd": 150, "xp": 19, "d": [6, 12], "ai": "skittish", "rdmg": [2, 4], "range": 5, "flags": []},
	"cultist": {"g": "c", "c": "#ff5d5d", "hp": 17, "ac": 4, "hit": 4, "dmg": [1, 4], "spd": 100, "xp": 23, "d": [7, 12], "ai": "ranged", "rdmg": [2, 5], "range": 6, "flags": []},
	"troll": {"g": "T", "c": "#5fd39a", "hp": 32, "ac": 5, "hit": 5, "dmg": [2, 6], "spd": 100, "xp": 36, "d": [8, 12], "ai": "melee", "flags": ["regen", "sleeps"]},
	"wraith": {"g": "W", "c": "#a3b1ff", "hp": 24, "ac": 6, "hit": 6, "dmg": [1, 10], "spd": 100, "xp": 36, "d": [9, 12], "ai": "melee", "flags": ["drain"]},
	"ogre": {"g": "O", "c": "#d9964f", "hp": 38, "ac": 5, "hit": 5, "dmg": [2, 8], "spd": 75, "xp": 42, "d": [9, 12], "ai": "melee", "flags": ["sleeps"]},
	"king": {"g": "K", "c": "#ffd166", "hp": 110, "ac": 7, "hit": 8, "dmg": [2, 7], "spd": 100, "xp": 250, "d": [99, 99], "ai": "boss", "rdmg": [2, 6], "range": 7, "flags": ["summon"]},
}

# Item classes: weapon, missile, armour, potion, scroll, wand, food, gold, amulet
const ITEMS := {
	"dagger": {"cls": "weapon", "g": ")", "c": "#cfd8e6", "dmg": [1, 4], "throw": [1, 4], "d": 1, "w": 6},
	"short_sword": {"cls": "weapon", "g": ")", "c": "#cfd8e6", "dmg": [1, 6], "d": 1, "w": 5},
	"spear": {"cls": "weapon", "g": ")", "c": "#d8b98a", "dmg": [1, 8], "throw": [1, 6], "d": 2, "w": 4},
	"mace": {"cls": "weapon", "g": ")", "c": "#b0b8c8", "dmg": [2, 4], "d": 2, "w": 4},
	"long_sword": {"cls": "weapon", "g": ")", "c": "#e8f0ff", "dmg": [1, 10], "d": 4, "w": 3},
	"battle_axe": {"cls": "weapon", "g": ")", "c": "#ffb070", "dmg": [2, 6], "d": 6, "w": 2},
	"darts": {"cls": "missile", "g": "/", "c": "#9fe0ff", "throw": [1, 4], "d": 1, "w": 5},
	"leather": {"cls": "armour", "g": "[", "c": "#c58b55", "ac": 2, "d": 1, "w": 5},
	"ring_mail": {"cls": "armour", "g": "[", "c": "#b8c0cc", "ac": 3, "d": 2, "w": 4},
	"chain_mail": {"cls": "armour", "g": "[", "c": "#d8e0ec", "ac": 4, "d": 4, "w": 3},
	"scale_mail": {"cls": "armour", "g": "[", "c": "#9fd6c0", "ac": 5, "d": 6, "w": 2},
	"plate": {"cls": "armour", "g": "[", "c": "#f2f6ff", "ac": 7, "d": 8, "w": 1},
	"ration": {"cls": "food", "g": "%", "c": "#e8c07a", "food": 900, "d": 1, "w": 6},
	"apple": {"cls": "food", "g": "%", "c": "#ff6b6b", "food": 300, "d": 1, "w": 4},
	"gold": {"cls": "gold", "g": "$", "c": "#ffd166", "d": 1, "w": 0},
	"amulet": {"cls": "amulet", "g": "\"", "c": "#ffe08a", "d": 99, "w": 0},
	# potions
	"p_heal": {"cls": "potion", "g": "!", "d": 1, "w": 9},
	"p_vigor": {"cls": "potion", "g": "!", "d": 3, "w": 3},
	"p_might": {"cls": "potion", "g": "!", "d": 2, "w": 3},
	"p_haste": {"cls": "potion", "g": "!", "d": 2, "w": 4},
	"p_sight": {"cls": "potion", "g": "!", "d": 1, "w": 4},
	"p_confuse": {"cls": "potion", "g": "!", "d": 1, "w": 4},
	"p_poison": {"cls": "potion", "g": "!", "d": 1, "w": 4},
	"p_sleep": {"cls": "potion", "g": "!", "d": 2, "w": 3},
	"p_xp": {"cls": "potion", "g": "!", "d": 4, "w": 2},
	# scrolls
	"s_identify": {"cls": "scroll", "g": "?", "d": 1, "w": 9},
	"s_teleport": {"cls": "scroll", "g": "?", "d": 1, "w": 4},
	"s_enchant_w": {"cls": "scroll", "g": "?", "d": 1, "w": 4},
	"s_enchant_a": {"cls": "scroll", "g": "?", "d": 1, "w": 4},
	"s_map": {"cls": "scroll", "g": "?", "d": 1, "w": 4},
	"s_fear": {"cls": "scroll", "g": "?", "d": 2, "w": 3},
	"s_fire": {"cls": "scroll", "g": "?", "d": 2, "w": 3},
	"s_summon": {"cls": "scroll", "g": "?", "d": 2, "w": 3},
	# wands
	"w_lightning": {"cls": "wand", "g": "~", "d": 2, "w": 3},
	"w_sleep": {"cls": "wand", "g": "~", "d": 1, "w": 3},
	"w_force": {"cls": "wand", "g": "~", "d": 1, "w": 3},
}

const POTION_KINDS := ["p_heal", "p_vigor", "p_might", "p_haste", "p_sight", "p_confuse", "p_poison", "p_sleep", "p_xp"]
const SCROLL_KINDS := ["s_identify", "s_teleport", "s_enchant_w", "s_enchant_a", "s_map", "s_fear", "s_fire", "s_summon"]
const WAND_KINDS := ["w_lightning", "w_sleep", "w_force"]

# Appearance pools (translation keys), shuffled per run.
const POTION_COLORS := [
	["C_RED", "#ff5a5a"], ["C_BLUE", "#5aa0ff"], ["C_GREEN", "#5ae08a"], ["C_AMBER", "#ffb84d"],
	["C_VIOLET", "#b77dff"], ["C_PINK", "#ff8ad8"], ["C_TEAL", "#4fe0d4"], ["C_MILKY", "#e8eef5"],
	["C_BLACK", "#6a6f80"], ["C_GOLDEN", "#ffd84d"], ["C_FIZZY", "#c8ff6b"],
]
const WAND_WOODS := [["W_OAK", "#c08a50"], ["W_BONE", "#ece2c6"], ["W_ASH", "#bfb4a0"], ["W_IRON", "#9aa8b8"], ["W_GLASS", "#a8f0ff"], ["W_EBONY", "#7a6a8c"]]
const SYLLABLES := ["ka", "zor", "mi", "vel", "tho", "ran", "qu", "esh", "lo", "dra", "nim", "ul", "fae", "gor", "ix", "sel", "bru", "ta", "om", "yen"]
const SCROLL_COLOR := "#f1e3b8"

const TRAPS := ["dart", "teleport", "alarm"]

const HUNGER_MAX := 2000
const HUNGER_START := 1400
const HUNGRY := 300
const WEAK := 80

const XP_LEVELS := [0, 20, 45, 90, 170, 300, 500, 800, 1250, 1900, 2800, 4000, 5600, 8000]


static func mon(id: String) -> Dictionary:
	return MONSTERS[id]


static func item(id: String) -> Dictionary:
	return ITEMS[id]


static func cls(id: String) -> String:
	return ITEMS[id].cls


static func stackable(id: String) -> bool:
	var c: String = ITEMS[id].cls
	return c in ["potion", "scroll", "food", "missile", "gold"]


## Monster ids eligible at `depth` (boss excluded).
static func monsters_for(depth: int) -> Array:
	var out := []
	for id in MONSTERS:
		var d: Array = MONSTERS[id].d
		if depth >= d[0] and depth <= d[1]:
			out.append(id)
	return out
